-- Business logic (HLD v0.4 §7, §9). All money operations go through these
-- SECURITY DEFINER functions; the ledger is never written directly by clients.

-- ================= helpers =================
create function today_ist() returns date language sql stable as $$
  select (now() at time zone 'Asia/Kolkata')::date
$$;

create function is_service() returns boolean language sql stable as $$
  select coalesce(auth.role(), '') = 'service_role'
$$;

create function my_property_id() returns uuid language sql stable security definer set search_path = public as $$
  select property_id from app_user where id = auth.uid() and active
$$;

create function is_owner() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from app_user where id = auth.uid() and active and role = 'OWNER')
$$;

create function my_tenant_id() returns uuid language sql stable security definer set search_path = public as $$
  select tenant_id from app_user where id = auth.uid() and active and role = 'TENANT'
$$;

create function my_tenancy_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  select o.tenancy_id
  from occupant o
  join app_user u on u.tenant_id = o.tenant_id
  where u.id = auth.uid() and u.active and u.role = 'TENANT' and o.app_access
$$;

create function my_room_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  select t.room_id from tenancy t where t.id in (select my_tenancy_ids())
$$;

create function require_owner() returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  if is_service() then
    select id into v from property order by created_at limit 1;
    return v;
  end if;
  select property_id into v from app_user where id = auth.uid() and active and role = 'OWNER';
  if v is null then
    raise exception 'Only the owner can do this' using errcode = '42501';
  end if;
  return v;
end $$;

-- Returns the tenancy row if the caller is its owner (or, when p_tenant_ok, one of its occupants).
create function _tenancy_for(p_tenancy uuid, p_tenant_ok boolean default false)
returns tenancy language plpgsql stable security definer set search_path = public as $$
declare t tenancy;
begin
  select * into t from tenancy where id = p_tenancy;
  if t.id is null then raise exception 'Tenancy not found'; end if;
  if is_service() or (is_owner() and t.property_id = my_property_id()) then return t; end if;
  if p_tenant_ok and p_tenancy in (select my_tenancy_ids()) then return t; end if;
  raise exception 'Not allowed' using errcode = '42501';
end $$;

create function setting_value(p_property uuid, p_key text, p_on date default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select value from setting
  where property_id = p_property and key = p_key and effective_from <= coalesce(p_on, today_ist())
  order by effective_from desc, id desc limit 1
$$;

create function setting_num(p_property uuid, p_key text, p_on date default null, p_default numeric default 0)
returns numeric language sql stable as $$
  select coalesce((setting_value(p_property, p_key, p_on) #>> '{}')::numeric, p_default)
$$;

-- Rent cycles are anchored to the move-in date; Postgres month arithmetic
-- clamps 29–31 to the month end (D3).
create function cycle_end_of(p_start date, p_cycle_start date) returns date language sql immutable as $$
  select ((p_start + make_interval(months =>
            (extract(year from p_cycle_start)::int * 12 + extract(month from p_cycle_start)::int)
          - (extract(year from p_start)::int * 12 + extract(month from p_start)::int) + 1))::date - 1)
$$;

create function tenancy_balance(p_tenancy uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(debit) - sum(credit), 0) from ledger_entry where tenancy_id = p_tenancy
$$;

create function advance_held(p_tenancy uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount), 0) from advance where tenancy_id = p_tenancy
$$;

create function _post(p_t tenancy, p_date date, p_kind ledger_kind, p_amount numeric,
                      p_note text, p_bill uuid default null, p_payment uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_amount = 0 then return; end if;
  insert into ledger_entry (property_id, tenancy_id, entry_date, kind, debit, credit, bill_id, payment_id, note, created_by)
  values (p_t.property_id, p_t.id, p_date, p_kind,
          greatest(p_amount, 0), greatest(-p_amount, 0), p_bill, p_payment, p_note, auth.uid());
end $$;

-- FIFO: credits pay the oldest debits first; bill status follows.
create function refresh_bill_status(p_tenancy uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_avail numeric;
  r record;
  v_left numeric;
begin
  -- a cancelled payment (PAYMENT_VOID) takes back its credit instead of being a new due
  select coalesce(sum(credit), 0) - coalesce(sum(debit) filter (where kind = 'PAYMENT_VOID'), 0)
    into v_avail from ledger_entry where tenancy_id = p_tenancy;
  for r in select bill_id, debit from ledger_entry
           where tenancy_id = p_tenancy and debit > 0 and kind <> 'PAYMENT_VOID' order by entry_date, id loop
    v_left := v_avail;
    v_avail := greatest(v_avail - r.debit, 0);
    if r.bill_id is not null then
      update bill set status = case when v_left >= r.debit then 'PAID'::bill_status
                                    when v_left > 0 then 'PARTIAL'::bill_status
                                    else 'ISSUED'::bill_status end
      where id = r.bill_id and status <> 'DRAFT';
    end if;
  end loop;
  update bill b set status = 'PAID'
  where b.tenancy_id = p_tenancy and b.status <> 'DRAFT' and b.total <= 0;
end $$;

-- ================= billing =================
-- Builds a DRAFT bill for [p_cycle_start, p_cycle_end]. For a final bill, rent is
-- pro-rated by days stayed in the (full) cycle.
create function _build_bill(p_tenancy uuid, p_cycle_start date, p_cycle_end date,
                            p_is_final boolean default false, p_final_reading uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  t tenancy;
  v_bill uuid;
  v_full_end date;
  v_days int; v_full int;
  v_rent numeric;
  base meter_reading; newr meter_reading;
  v_units numeric; v_rate numeric;
  v_fee numeric; v_grace int; prev bill;
  v_sort int := 0;
  c record;
begin
  select * into t from tenancy where id = p_tenancy for update;

  insert into bill (property_id, tenancy_id, cycle_start, cycle_end, bill_date, opening_balance,
                    is_final, prev_elec_reading_id, created_by)
  values (t.property_id, t.id, p_cycle_start, p_cycle_end, p_cycle_end, tenancy_balance(t.id),
          p_is_final, t.elec_last_reading_id, auth.uid())
  returning id into v_bill;

  -- Rent
  v_full_end := cycle_end_of(t.start_date, p_cycle_start);
  v_full := v_full_end - p_cycle_start + 1;
  v_days := greatest(p_cycle_end - p_cycle_start + 1, 0);
  v_rent := case when v_days >= v_full then t.monthly_rent
                 else round(t.monthly_rent * v_days / v_full) end;
  if v_days > 0 then
    v_sort := v_sort + 1;
    insert into bill_line (bill_id, kind, label, qty, rate, amount, meta, sort)
    values (v_bill, 'RENT', 'Rent', v_days, t.monthly_rent, v_rent,
            jsonb_build_object('from', p_cycle_start, 'to', p_cycle_end, 'days', v_days, 'cycle_days', v_full), v_sort);
  end if;

  -- Electricity: the second clock (D17). Charge units up to the latest reading
  -- on/before the bill date; if none is new, nothing is charged now and it rolls on.
  select * into base from meter_reading where id = t.elec_last_reading_id;
  if p_final_reading is not null then
    select * into newr from meter_reading where id = p_final_reading;
  else
    select * into newr from meter_reading
    where room_id = t.room_id and reading_date <= p_cycle_end and reading_date >= t.start_date
      and kind in ('MONTHLY', 'MOVE_OUT', 'SHIFT')
      and (base.id is null or reading_date > base.reading_date)
    order by reading_date desc, created_at desc limit 1;
  end if;

  if newr.id is not null then
    if base.id is null then
      update tenancy set elec_last_reading_id = newr.id where id = t.id;   -- first reading = baseline
    elsif newr.id <> base.id then
      v_units := greatest(newr.value - base.value, 0);
      v_rate := setting_num(t.property_id, 'electricity_rate', newr.reading_date, 12);
      v_sort := v_sort + 1;
      insert into bill_line (bill_id, kind, label, qty, rate, amount, meta, sort)
      values (v_bill, 'ELECTRICITY', 'Light bill', v_units, v_rate, round(v_units * v_rate, 2),
              jsonb_build_object('from_reading', base.value, 'to_reading', newr.value,
                                 'from_date', base.reading_date, 'to_date', newr.reading_date,
                                 'meter_went_back', newr.value < base.value), v_sort);
      update meter_reading set billed_bill_id = v_bill where id = newr.id;
      update tenancy set elec_last_reading_id = newr.id where id = t.id;
    end if;
  end if;

  -- Recurring and one-off charges (D6)
  for c in select * from charge
           where tenancy_id = t.id and active and start_date <= p_cycle_end
             and ((kind = 'RECURRING' and (end_date is null or end_date >= p_cycle_start))
               or (kind = 'ONE_OFF' and billed_bill_id is null))
           order by created_at loop
    v_sort := v_sort + 1;
    insert into bill_line (bill_id, kind, label, amount, meta, sort)
    values (v_bill, 'CHARGE', c.label, c.amount, jsonb_build_object('charge_id', c.id, 'charge_kind', c.kind), v_sort);
    if c.kind = 'ONE_OFF' then update charge set billed_bill_id = v_bill where id = c.id; end if;
  end loop;

  -- Late fee (custom, off by default – D20)
  v_fee := coalesce(t.late_fee, setting_num(t.property_id, 'late_fee', p_cycle_end, 0));
  if v_fee > 0 then
    v_grace := coalesce(t.grace_days, setting_num(t.property_id, 'grace_days', p_cycle_end, 0)::int);
    select * into prev from bill where tenancy_id = t.id and id <> v_bill and status in ('ISSUED', 'PARTIAL')
      order by cycle_start desc limit 1;
    if prev.id is not null and prev.due_date is not null and prev.due_date + v_grace < p_cycle_end then
      v_sort := v_sort + 1;
      insert into bill_line (bill_id, kind, label, amount, meta, sort)
      values (v_bill, 'LATE_FEE', 'Late fee', v_fee, jsonb_build_object('for_bill', prev.bill_no), v_sort);
    end if;
  end if;

  update bill set total = coalesce((select sum(amount) from bill_line where bill_id = v_bill), 0) where id = v_bill;
  update tenancy set next_cycle_start = p_cycle_end + 1 where id = t.id;
  return v_bill;
end $$;

create function _recalc_bill_total(p_bill uuid) returns void language sql security definer set search_path = public as $$
  update bill set total = coalesce((select sum(amount) from bill_line where bill_id = p_bill), 0) where id = p_bill
$$;

create function _issue(p_bill uuid) returns void language plpgsql security definer set search_path = public as $$
declare b bill; t tenancy; v_due int;
begin
  select * into b from bill where id = p_bill for update;
  if b.status <> 'DRAFT' then return; end if;
  select * into t from tenancy where id = b.tenancy_id;
  v_due := coalesce(t.due_after_days, setting_num(t.property_id, 'due_after_bill_days', b.bill_date, 0)::int);
  update bill set status = 'ISSUED', issued_at = now(), due_date = b.bill_date + v_due where id = p_bill;
  perform _post(t, b.bill_date, 'BILL', b.total, 'Bill #' || b.bill_no, p_bill);
  perform refresh_bill_status(t.id);
end $$;

create function _generate_for_tenancy(p_tenancy uuid, p_as_of date, p_auto_issue boolean) returns int
language plpgsql security definer set search_path = public as $$
declare t tenancy; v_end date; v_leave date; v_bill uuid; n int := 0;
begin
  loop
    select * into t from tenancy where id = p_tenancy;
    exit when t.status not in ('ACTIVE', 'ON_NOTICE');
    v_end := cycle_end_of(t.start_date, t.next_cycle_start);
    exit when v_end > p_as_of;
    -- A tenant on notice gets a final bill at settlement instead of the cycle that contains the leave date.
    select leave_on into v_leave from notice_to_vacate
      where tenancy_id = t.id and not withdrawn order by created_at desc limit 1;
    exit when t.status = 'ON_NOTICE' and v_leave is not null and v_leave <= v_end;
    v_bill := _build_bill(t.id, t.next_cycle_start, v_end);
    if p_auto_issue then perform _issue(v_bill); end if;
    n := n + 1;
    exit when n > 24;  -- safety
  end loop;
  return n;
end $$;

create function _generate_due_bills(p_property uuid, p_as_of date) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; v_auto boolean;
begin
  v_auto := coalesce((setting_value(p_property, 'auto_issue', p_as_of) #>> '{}')::boolean, false);
  for r in select id from tenancy where property_id = p_property and status in ('ACTIVE', 'ON_NOTICE') loop
    n := n + _generate_for_tenancy(r.id, p_as_of, v_auto);
  end loop;
  return n;
end $$;

create function generate_due_bills(p_as_of date default null) returns int
language plpgsql security definer set search_path = public as $$
begin
  return _generate_due_bills(require_owner(), coalesce(p_as_of, today_ist()));
end $$;

-- Daily GitHub Actions job (service role): due bills + keeps the free project awake.
create function cron_daily(p_as_of date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not is_service() then raise exception 'service role only' using errcode = '42501'; end if;
  for r in select id from property loop
    n := n + _generate_due_bills(r.id, coalesce(p_as_of, today_ist()));
  end loop;
  return jsonb_build_object('bills_created', n, 'as_of', coalesce(p_as_of, today_ist()));
end $$;

create function issue_bill(p_bill uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bill;
begin
  select * into b from bill where id = p_bill;
  perform _tenancy_for(b.tenancy_id);
  perform _issue(p_bill);
end $$;

create function issue_all_drafts() returns int
language plpgsql security definer set search_path = public as $$
declare v_prop uuid := require_owner(); r record; n int := 0;
begin
  for r in select id from bill where property_id = v_prop and status = 'DRAFT' order by cycle_start loop
    perform _issue(r.id); n := n + 1;
  end loop;
  return n;
end $$;

create function add_bill_line(p_bill uuid, p_label text, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
declare b bill;
begin
  select * into b from bill where id = p_bill;
  perform _tenancy_for(b.tenancy_id);
  if b.status <> 'DRAFT' then raise exception 'Bill already sent. Use an adjustment instead.'; end if;
  insert into bill_line (bill_id, kind, label, amount, sort)
  values (p_bill, 'OTHER', p_label, p_amount, 100);
  perform _recalc_bill_total(p_bill);
end $$;

create function remove_bill_line(p_line uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bill; l bill_line;
begin
  select * into l from bill_line where id = p_line;
  select * into b from bill where id = l.bill_id;
  perform _tenancy_for(b.tenancy_id);
  if b.status <> 'DRAFT' then raise exception 'Bill already sent. Use an adjustment instead.'; end if;
  if l.kind = 'ELECTRICITY' then
    update meter_reading set billed_bill_id = null where billed_bill_id = b.id;
    update tenancy set elec_last_reading_id = b.prev_elec_reading_id where id = b.tenancy_id;
  elsif l.kind = 'CHARGE' then
    update charge set billed_bill_id = null where billed_bill_id = b.id and id = (l.meta->>'charge_id')::uuid;
  end if;
  delete from bill_line where id = p_line;
  perform _recalc_bill_total(b.id);
end $$;

-- Undo a draft (only the newest bill of a tenancy) so it can be regenerated.
create function discard_draft_bill(p_bill uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bill;
begin
  select * into b from bill where id = p_bill;
  perform _tenancy_for(b.tenancy_id);
  if b.status <> 'DRAFT' then raise exception 'Only a draft bill can be discarded'; end if;
  if exists (select 1 from bill where tenancy_id = b.tenancy_id and cycle_start > b.cycle_start) then
    raise exception 'Discard the newer bill first';
  end if;
  update tenancy set next_cycle_start = b.cycle_start, elec_last_reading_id = b.prev_elec_reading_id
  where id = b.tenancy_id;
  delete from bill where id = p_bill;   -- readings/charges are released by ON DELETE SET NULL
end $$;

-- ================= meter readings =================
-- p_items: [{"room_id": "...", "value": 1234.5, "note": "..."}]
create function add_readings(p_date date, p_items jsonb, p_kind reading_kind default 'MONTHLY', p_force boolean default false)
returns int language plpgsql security definer set search_path = public as $$
declare v_prop uuid := require_owner(); it jsonb; v_room uuid; v_val numeric; v_prev numeric; n int := 0;
begin
  for it in select * from jsonb_array_elements(p_items) loop
    v_room := (it->>'room_id')::uuid;
    v_val := (it->>'value')::numeric;
    if not exists (select 1 from room where id = v_room and property_id = v_prop) then
      raise exception 'Room not found';
    end if;
    select value into v_prev from meter_reading
      where room_id = v_room and reading_date <= p_date and not (reading_date = p_date and kind = p_kind)
      order by reading_date desc, created_at desc limit 1;
    if v_prev is not null and v_val < v_prev and not p_force then
      raise exception 'Reading % for room % is less than last reading %', v_val,
        (select number from room where id = v_room), v_prev using errcode = 'P0001';
    end if;
    if exists (select 1 from meter_reading where room_id = v_room and reading_date = p_date and kind = p_kind
               and billed_bill_id is not null) then
      raise exception 'This reading is already billed';
    end if;
    insert into meter_reading (property_id, room_id, reading_date, value, kind, note, created_by)
    values (v_prop, v_room, p_date, v_val, p_kind, it->>'note', auth.uid())
    on conflict (room_id, reading_date, kind) do update set value = excluded.value, note = excluded.note;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ================= onboarding =================
create function _insert_tenant(p_property uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into tenant
  select (jsonb_populate_record(null::tenant,
            jsonb_build_object('extra', '{}'::jsonb)
            || (p - 'id' - 'property_id' - 'created_at' - 'is_primary' - 'app_access')
            || jsonb_build_object('id', v_id, 'property_id', p_property, 'created_at', now()))).*;
  return v_id;
end $$;

-- p: {room_id, start_date, monthly_rent, advance_amount, advance_date, move_in_reading,
--     opening_balance, due_after_days, grace_days, late_fee, notes,
--     tenants: [{full_name, phone, ..., is_primary, app_access}] | existing tenant_id,
--     charges: [{label, amount}]}
create function onboard_tenant(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_prop uuid := require_owner();
  v_room room; v_start date; v_tenancy uuid; v_primary uuid; v_tid uuid;
  v_reading uuid; tj jsonb; i int := 0; v_adv numeric; ch jsonb; t tenancy;
begin
  select * into v_room from room where id = (p->>'room_id')::uuid and property_id = v_prop;
  if v_room.id is null then raise exception 'Room not found'; end if;
  if exists (select 1 from tenancy where room_id = v_room.id and status in ('ACTIVE', 'ON_NOTICE')) then
    raise exception 'Room % already has a tenant', v_room.number;
  end if;
  if jsonb_array_length(coalesce(p->'tenants', '[]')) = 0 then raise exception 'Add at least one person'; end if;
  v_start := coalesce((p->>'start_date')::date, today_ist());

  -- people
  create temp table if not exists _new_occ (tenant_id uuid, is_primary boolean, app_access boolean) on commit drop;
  delete from _new_occ;
  for tj in select * from jsonb_array_elements(p->'tenants') loop
    i := i + 1;
    if tj ? 'tenant_id' then v_tid := (tj->>'tenant_id')::uuid;
    else v_tid := _insert_tenant(v_prop, tj); end if;
    insert into _new_occ values (v_tid, coalesce((tj->>'is_primary')::boolean, i = 1), coalesce((tj->>'app_access')::boolean, false));
  end loop;
  select tenant_id into v_primary from _new_occ where is_primary limit 1;
  if v_primary is null then select tenant_id into v_primary from _new_occ limit 1; end if;

  -- move-in meter reading = electricity baseline
  if p ? 'move_in_reading' and p->>'move_in_reading' is not null then
    insert into meter_reading (property_id, room_id, reading_date, value, kind, created_by)
    values (v_prop, v_room.id, v_start, (p->>'move_in_reading')::numeric, 'MOVE_IN', auth.uid())
    on conflict (room_id, reading_date, kind) do update set value = excluded.value
    returning id into v_reading;
  else
    select id into v_reading from meter_reading where room_id = v_room.id and reading_date <= v_start
      order by reading_date desc, created_at desc limit 1;
  end if;

  insert into tenancy (property_id, room_id, primary_tenant_id, start_date, monthly_rent, next_cycle_start,
                       elec_last_reading_id, due_after_days, grace_days, late_fee, notes)
  values (v_prop, v_room.id, v_primary, v_start,
          coalesce((p->>'monthly_rent')::numeric, v_room.default_rent, 0), v_start, v_reading,
          (p->>'due_after_days')::int, (p->>'grace_days')::int, (p->>'late_fee')::numeric, p->>'notes')
  returning id into v_tenancy;

  insert into occupant (tenancy_id, tenant_id, is_primary, app_access, joined_on)
  select v_tenancy, tenant_id, tenant_id = v_primary, app_access, v_start from _new_occ;

  v_adv := coalesce((p->>'advance_amount')::numeric, 0);
  if v_adv <> 0 then
    insert into advance (tenancy_id, amount, txn_date, note, created_by)
    values (v_tenancy, v_adv, coalesce((p->>'advance_date')::date, v_start), 'Advance received', auth.uid());
  end if;

  select * into t from tenancy where id = v_tenancy;
  if coalesce((p->>'opening_balance')::numeric, 0) <> 0 then
    perform _post(t, v_start, 'OPENING', (p->>'opening_balance')::numeric, 'Opening balance');
  end if;

  for ch in select * from jsonb_array_elements(coalesce(p->'charges', '[]')) loop
    insert into charge (tenancy_id, label, amount, kind, start_date, created_by)
    values (v_tenancy, ch->>'label', (ch->>'amount')::numeric,
            coalesce((ch->>'kind')::charge_kind, 'RECURRING'), coalesce((ch->>'start_date')::date, v_start), auth.uid());
  end loop;

  update room set status = 'OCCUPIED' where id = v_room.id;
  return v_tenancy;
end $$;

create function add_occupant(p_tenancy uuid, p_person jsonb, p_joined date default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare t tenancy; v_tid uuid;
begin
  t := _tenancy_for(p_tenancy);
  if p_person ? 'tenant_id' then v_tid := (p_person->>'tenant_id')::uuid;
  else v_tid := _insert_tenant(t.property_id, p_person); end if;
  insert into occupant (tenancy_id, tenant_id, is_primary, app_access, joined_on)
  values (t.id, v_tid, false, coalesce((p_person->>'app_access')::boolean, false), coalesce(p_joined, today_ist()))
  on conflict (tenancy_id, tenant_id) do update set left_on = null;
  return v_tid;
end $$;

create function remove_occupant(p_tenancy uuid, p_tenant uuid, p_left date default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _tenancy_for(p_tenancy);
  update occupant set left_on = coalesce(p_left, today_ist()), app_access = false
  where tenancy_id = p_tenancy and tenant_id = p_tenant and not is_primary;
  if not found then raise exception 'Cannot remove the main tenant; use move-out instead'; end if;
end $$;

-- ================= charges & adjustments =================
create function add_charge(p_tenancy uuid, p_label text, p_amount numeric, p_kind charge_kind default 'ONE_OFF',
                           p_start date default null, p_end date default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare t tenancy; v uuid;
begin
  t := _tenancy_for(p_tenancy);
  if coalesce(trim(p_label), '') = '' then raise exception 'Name of the charge is needed'; end if;
  insert into charge (tenancy_id, label, amount, kind, start_date, end_date, created_by)
  values (t.id, trim(p_label), p_amount, p_kind, coalesce(p_start, today_ist()), p_end, auth.uid())
  returning id into v;
  return v;
end $$;

create function stop_charge(p_charge uuid, p_end date default null) returns void
language plpgsql security definer set search_path = public as $$
declare c charge;
begin
  select * into c from charge where id = p_charge;
  perform _tenancy_for(c.tenancy_id);
  if c.kind = 'ONE_OFF' and c.billed_bill_id is null then
    update charge set active = false where id = p_charge;
  else
    update charge set end_date = coalesce(p_end, today_ist()) where id = p_charge;
  end if;
end $$;

-- +amount = tenant owes more, -amount = reduce dues. Reason is required (D8).
create function adjust(p_tenancy uuid, p_amount numeric, p_reason text, p_date date default null) returns void
language plpgsql security definer set search_path = public as $$
declare t tenancy;
begin
  t := _tenancy_for(p_tenancy);
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please write a reason'; end if;
  if p_amount = 0 then raise exception 'Amount cannot be 0'; end if;
  perform _post(t, coalesce(p_date, today_ist()), 'ADJUSTMENT', p_amount, trim(p_reason));
  perform refresh_bill_status(t.id);
end $$;

-- ================= payments (D7, Splitwise-style) =================
-- p_splits: [{"mode": "CASH", "amount": 2000, "ref": ""}, {"mode": "PHONEPE", "amount": 500}]
create function record_payment(p_tenancy uuid, p_paid_on date, p_splits jsonb,
                               p_note text default null, p_idempotency_key text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare t tenancy; v_id uuid; v_amt numeric; s jsonb;
begin
  t := _tenancy_for(p_tenancy);
  if p_idempotency_key is not null then
    select id into v_id from payment where idempotency_key = p_idempotency_key;
    if v_id is not null then return v_id; end if;
  end if;
  select coalesce(sum((x->>'amount')::numeric), 0) into v_amt from jsonb_array_elements(p_splits) x;
  if v_amt <= 0 then raise exception 'Amount must be more than 0'; end if;
  insert into payment (property_id, tenancy_id, paid_on, amount, status, note, idempotency_key,
                       created_by, confirmed_by, confirmed_at)
  values (t.property_id, t.id, coalesce(p_paid_on, today_ist()), v_amt, 'CONFIRMED', p_note, p_idempotency_key,
          auth.uid(), auth.uid(), now())
  returning id into v_id;
  for s in select * from jsonb_array_elements(p_splits) loop
    if (s->>'amount')::numeric > 0 then
      insert into payment_split (payment_id, mode, amount, ref)
      values (v_id, (s->>'mode')::payment_mode, (s->>'amount')::numeric, s->>'ref');
    end if;
  end loop;
  perform _post(t, coalesce(p_paid_on, today_ist()), 'PAYMENT', -v_amt, p_note, null, v_id);
  perform refresh_bill_status(t.id);
  return v_id;
end $$;

-- Tenant says "I paid" -> waits for owner (D7).
create function claim_payment(p_tenancy uuid, p_paid_on date, p_amount numeric, p_mode payment_mode,
                              p_ref text default null, p_note text default null, p_proof_path text default null,
                              p_idempotency_key text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare t tenancy; v_id uuid;
begin
  t := _tenancy_for(p_tenancy, true);
  if p_idempotency_key is not null then
    select id into v_id from payment where idempotency_key = p_idempotency_key;
    if v_id is not null then return v_id; end if;
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be more than 0'; end if;
  insert into payment (property_id, tenancy_id, paid_on, amount, status, claimed_by_tenant, note, proof_path,
                       idempotency_key, created_by)
  values (t.property_id, t.id, coalesce(p_paid_on, today_ist()), p_amount, 'PENDING_CONFIRM', true, p_note,
          p_proof_path, p_idempotency_key, auth.uid())
  returning id into v_id;
  insert into payment_split (payment_id, mode, amount, ref) values (v_id, p_mode, p_amount, p_ref);
  return v_id;
end $$;

create function confirm_payment(p_payment uuid, p_approve boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare p payment; t tenancy;
begin
  select * into p from payment where id = p_payment for update;
  t := _tenancy_for(p.tenancy_id);
  if p.status <> 'PENDING_CONFIRM' then raise exception 'Already handled'; end if;
  if p_approve then
    update payment set status = 'CONFIRMED', confirmed_by = auth.uid(), confirmed_at = now() where id = p.id;
    perform _post(t, p.paid_on, 'PAYMENT', -p.amount, coalesce(p.note, 'Paid (tenant)'), null, p.id);
    perform refresh_bill_status(t.id);
  else
    update payment set status = 'REJECTED', reject_reason = p_reason, confirmed_by = auth.uid(), confirmed_at = now()
    where id = p.id;
  end if;
end $$;

-- Undo / cancel a confirmed payment with a reversing entry.
create function void_payment(p_payment uuid, p_reason text default 'Cancelled') returns void
language plpgsql security definer set search_path = public as $$
declare p payment; t tenancy;
begin
  select * into p from payment where id = p_payment for update;
  t := _tenancy_for(p.tenancy_id);
  if p.status <> 'CONFIRMED' then raise exception 'Only a received payment can be cancelled'; end if;
  update payment set status = 'VOID', reject_reason = p_reason where id = p.id;
  perform _post(t, today_ist(), 'PAYMENT_VOID', p.amount, coalesce(p_reason, 'Cancelled'), null, p.id);
  perform refresh_bill_status(t.id);
end $$;

-- ================= notice & move-out (D5, D19) =================
create function give_notice(p_tenancy uuid, p_leave_on date, p_given_on date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t tenancy; v_given date := coalesce(p_given_on, today_ist()); v_period int; v_short int;
begin
  t := _tenancy_for(p_tenancy, true);
  if t.status not in ('ACTIVE', 'ON_NOTICE') then raise exception 'Tenant has already left'; end if;
  if p_leave_on < v_given then raise exception 'Leaving date cannot be before today'; end if;
  update notice_to_vacate set withdrawn = true where tenancy_id = t.id and not withdrawn;
  insert into notice_to_vacate (tenancy_id, given_on, leave_on, given_by_tenant, note, created_by)
  values (t.id, v_given, p_leave_on, not is_owner(), p_note, auth.uid());
  update tenancy set status = 'ON_NOTICE' where id = t.id;
  v_period := setting_num(t.property_id, 'notice_period_days', v_given, 30)::int;
  v_short := greatest(v_period - (p_leave_on - v_given), 0);
  return jsonb_build_object('notice_period_days', v_period, 'short_by_days', v_short,
                            'suggested_shortfall', round(t.monthly_rent * v_short / 30));
end $$;

create function withdraw_notice(p_tenancy uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t tenancy;
begin
  t := _tenancy_for(p_tenancy);
  update notice_to_vacate set withdrawn = true where tenancy_id = t.id and not withdrawn;
  update tenancy set status = 'ACTIVE' where id = t.id and status = 'ON_NOTICE';
end $$;

-- Final bill up to (and including) p_last_day, after billing any full cycles before it.
create function _final_bill(t_id uuid, p_last_day date, p_reading uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare t tenancy; v_end date; r record; v_bill uuid;
begin
  for r in select id from bill where tenancy_id = t_id and status = 'DRAFT' order by cycle_start loop
    perform _issue(r.id);
  end loop;
  loop
    select * into t from tenancy where id = t_id;
    v_end := cycle_end_of(t.start_date, t.next_cycle_start);
    exit when v_end > p_last_day;
    perform _issue(_build_bill(t.id, t.next_cycle_start, v_end));
  end loop;
  select * into t from tenancy where id = t_id;
  v_bill := _build_bill(t.id, t.next_cycle_start, greatest(p_last_day, t.next_cycle_start - 1), true, p_reading);
  return v_bill;
end $$;

-- p_extra: [{"label": "Broken window", "amount": 300}]
create function settle_move_out(p_tenancy uuid, p_leave_date date, p_final_reading numeric default null,
                                p_notice_shortfall numeric default 0, p_cleaning numeric default null,
                                p_extra jsonb default '[]', p_absconded boolean default false,
                                p_write_off_rest boolean default false, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t tenancy; v_reading uuid; v_bill uuid; v_clean numeric; e jsonb;
  v_bal numeric; v_held numeric; v_applied numeric := 0; v_refund numeric := 0; v_wo numeric := 0;
  v_outcome settlement_outcome;
begin
  t := _tenancy_for(p_tenancy);
  if t.status not in ('ACTIVE', 'ON_NOTICE') then raise exception 'Already settled'; end if;
  if p_leave_date < t.start_date then raise exception 'Leaving date is before move-in date'; end if;

  if p_final_reading is not null then
    insert into meter_reading (property_id, room_id, reading_date, value, kind, created_by)
    values (t.property_id, t.room_id, p_leave_date, p_final_reading, 'MOVE_OUT', auth.uid())
    on conflict (room_id, reading_date, kind) do update set value = excluded.value
    returning id into v_reading;
  end if;

  v_bill := _final_bill(t.id, p_leave_date, v_reading);

  v_clean := coalesce(p_cleaning, setting_num(t.property_id, 'cleaning_charge', p_leave_date, 500));
  if v_clean <> 0 then
    insert into bill_line (bill_id, kind, label, amount, sort) values (v_bill, 'CLEANING', 'Cleaning', v_clean, 50);
  end if;
  if coalesce(p_notice_shortfall, 0) <> 0 then
    insert into bill_line (bill_id, kind, label, amount, sort)
    values (v_bill, 'NOTICE_SHORTFALL', 'Short notice', p_notice_shortfall, 51);
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_extra, '[]')) loop
    insert into bill_line (bill_id, kind, label, amount, sort)
    values (v_bill, 'OTHER', e->>'label', (e->>'amount')::numeric, 60);
  end loop;
  perform _recalc_bill_total(v_bill);
  perform _issue(v_bill);

  -- Use the advance against dues, refund the rest (D5)
  select * into t from tenancy where id = p_tenancy;
  v_bal := tenancy_balance(t.id);
  v_held := advance_held(t.id);
  v_applied := least(v_held, greatest(v_bal, 0));
  if v_applied > 0 then
    perform _post(t, p_leave_date, 'ADVANCE_ADJ', -v_applied, 'Advance used');
    insert into advance (tenancy_id, amount, txn_date, note, created_by)
    values (t.id, -v_applied, p_leave_date, 'Used for dues', auth.uid());
    v_bal := v_bal - v_applied;
  end if;
  v_refund := v_held - v_applied;
  if v_refund > 0 then
    insert into advance (tenancy_id, amount, txn_date, note, created_by)
    values (t.id, -v_refund, p_leave_date, 'Returned to tenant', auth.uid());
  end if;
  if v_bal < 0 then  -- extra paid by tenant is also returned
    perform _post(t, p_leave_date, 'REFUND', -v_bal, 'Extra amount returned');
    v_refund := v_refund - v_bal;
    v_bal := 0;
  end if;
  if v_bal > 0 and (p_write_off_rest or p_absconded) then
    v_wo := v_bal;
    perform _post(t, p_leave_date, 'WRITE_OFF', -v_wo, coalesce(p_note, 'Written off'));
    v_bal := 0;
  end if;
  perform refresh_bill_status(t.id);

  v_outcome := case when v_wo > 0 then 'WRITTEN_OFF'
                    when v_bal > 0 then 'DUE_PENDING'
                    when v_refund > 0 then 'REFUNDED'
                    else 'SETTLED' end;
  insert into settlement (tenancy_id, leave_date, final_bill_id, advance_held, advance_applied, refund_amount,
                          written_off, balance_after, outcome, note, created_by)
  values (t.id, p_leave_date, v_bill, v_held, v_applied, v_refund, v_wo, v_bal, v_outcome, p_note, auth.uid());

  update tenancy set status = case when p_absconded then 'ABSCONDED'::tenancy_status else 'CLOSED'::tenancy_status end,
                     end_date = p_leave_date where id = t.id;
  update occupant set left_on = coalesce(left_on, p_leave_date) where tenancy_id = t.id;
  update charge set end_date = coalesce(end_date, p_leave_date) where tenancy_id = t.id and kind = 'RECURRING';
  update room set status = 'VACANT' where id = t.room_id;

  return jsonb_build_object('final_bill_id', v_bill, 'advance_held', v_held, 'advance_used', v_applied,
                            'refund', v_refund, 'written_off', v_wo, 'still_due', v_bal, 'outcome', v_outcome);
end $$;

-- ================= room shift (D10) =================
create function shift_room(p_tenancy uuid, p_new_room uuid, p_shift_date date,
                           p_old_room_reading numeric default null, p_new_room_reading numeric default null,
                           p_new_rent numeric default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  t tenancy; nr room; v_old_read uuid; v_new_read uuid; v_bill uuid; v_new uuid; v_bal numeric; v_held numeric;
  t_new tenancy;
begin
  t := _tenancy_for(p_tenancy);
  if t.status not in ('ACTIVE', 'ON_NOTICE') then raise exception 'Tenant has already left'; end if;
  select * into nr from room where id = p_new_room and property_id = t.property_id;
  if nr.id is null then raise exception 'Room not found'; end if;
  if nr.id = t.room_id then raise exception 'Choose a different room'; end if;
  if exists (select 1 from tenancy where room_id = nr.id and status in ('ACTIVE', 'ON_NOTICE')) then
    raise exception 'Room % is not empty', nr.number;
  end if;
  if p_shift_date <= t.start_date then raise exception 'Shift date must be after move-in date'; end if;

  if p_old_room_reading is not null then
    insert into meter_reading (property_id, room_id, reading_date, value, kind, created_by)
    values (t.property_id, t.room_id, p_shift_date, p_old_room_reading, 'SHIFT', auth.uid())
    on conflict (room_id, reading_date, kind) do update set value = excluded.value
    returning id into v_old_read;
  end if;
  v_bill := _final_bill(t.id, p_shift_date - 1, v_old_read);
  perform _issue(v_bill);

  if p_new_room_reading is not null then
    insert into meter_reading (property_id, room_id, reading_date, value, kind, created_by)
    values (t.property_id, nr.id, p_shift_date, p_new_room_reading, 'MOVE_IN', auth.uid())
    on conflict (room_id, reading_date, kind) do update set value = excluded.value
    returning id into v_new_read;
  else
    select id into v_new_read from meter_reading where room_id = nr.id and reading_date <= p_shift_date
      order by reading_date desc, created_at desc limit 1;
  end if;

  insert into tenancy (property_id, room_id, primary_tenant_id, start_date, monthly_rent, next_cycle_start,
                       elec_last_reading_id, due_after_days, grace_days, late_fee, previous_tenancy_id, notes)
  values (t.property_id, nr.id, t.primary_tenant_id, p_shift_date,
          coalesce(p_new_rent, nr.default_rent, t.monthly_rent), p_shift_date, v_new_read,
          t.due_after_days, t.grace_days, t.late_fee, t.id, t.notes)
  returning id into v_new;
  select * into t_new from tenancy where id = v_new;

  insert into occupant (tenancy_id, tenant_id, is_primary, app_access, joined_on)
  select v_new, tenant_id, is_primary, app_access, p_shift_date from occupant
  where tenancy_id = t.id and left_on is null;

  v_bal := tenancy_balance(t.id);
  if v_bal <> 0 then
    perform _post(t, p_shift_date, 'TRANSFER', -v_bal, 'Moved to room ' || nr.number);
    perform _post(t_new, p_shift_date, 'TRANSFER', v_bal,
                  'From room ' || (select number from room where id = t.room_id));
  end if;
  v_held := advance_held(t.id);
  if v_held <> 0 then
    insert into advance (tenancy_id, amount, txn_date, note, created_by) values
      (t.id, -v_held, p_shift_date, 'Moved to room ' || nr.number, auth.uid()),
      (v_new, v_held, p_shift_date, 'From room ' || (select number from room where id = t.room_id), auth.uid());
  end if;

  insert into charge (tenancy_id, label, amount, kind, start_date, end_date, created_by)
  select v_new, label, amount, kind, p_shift_date, end_date, auth.uid() from charge
  where tenancy_id = t.id and kind = 'RECURRING' and active and (end_date is null or end_date >= p_shift_date);
  update charge set end_date = p_shift_date - 1
  where tenancy_id = t.id and kind = 'RECURRING' and (end_date is null or end_date >= p_shift_date);

  update notice_to_vacate set withdrawn = true where tenancy_id = t.id and not withdrawn;
  update tenancy set status = 'SHIFTED', end_date = p_shift_date - 1 where id = t.id;
  update occupant set left_on = p_shift_date - 1 where tenancy_id = t.id and left_on is null;
  update room set status = 'VACANT' where id = t.room_id;
  update room set status = 'OCCUPIED' where id = nr.id;
  perform refresh_bill_status(t.id);
  perform refresh_bill_status(v_new);
  return v_new;
end $$;

-- ================= settings, misc =================
create function update_setting(p_key text, p_value jsonb, p_effective_from date default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_prop uuid := require_owner();
begin
  insert into setting (property_id, key, value, effective_from, created_by)
  values (v_prop, p_key, p_value, coalesce(p_effective_from, today_ist()), auth.uid())
  on conflict (property_id, key, effective_from) do update set value = excluded.value, created_by = excluded.created_by;
end $$;

create function current_settings() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from (
    select distinct on (key) key, value from setting
    where property_id = my_property_id() and effective_from <= today_ist()
      and (is_owner() or key in ('electricity_rate', 'notice_period_days', 'upi_id', 'upi_name',
                                 'owner_phone', 'reminder_en', 'reminder_hi', 'meter_reading_day'))
    order by key, effective_from desc, id desc) s
$$;

create function set_my_language(p_lang text) returns void
language sql security definer set search_path = public as $$
  update app_user set language = p_lang where id = auth.uid()
$$;

create function set_app_access(p_tenancy uuid, p_tenant uuid, p_access boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _tenancy_for(p_tenancy);
  update occupant set app_access = p_access where tenancy_id = p_tenancy and tenant_id = p_tenant;
end $$;

-- Historic import (§10): replays the paper ledger exactly as written.
-- p_entries: [{"type":"BILL","date":"2026-04-30","cycle_start":"2026-04-01","cycle_end":"2026-04-30",
--              "lines":[{"kind":"RENT","label":"Rent","amount":2500},{"kind":"ELECTRICITY","label":"Light bill","qty":40,"rate":12,"amount":480}]},
--             {"type":"PAYMENT","date":"2026-05-03","amount":2980,"mode":"CASH","note":"..."},
--             {"type":"ADJUSTMENT","date":"...","amount":-44,"note":"..."},
--             {"type":"OPENING","date":"...","amount":1200}]
create function import_history(p_tenancy uuid, p_entries jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare t tenancy; e jsonb; l jsonb; v_bill uuid; v_pay uuid; n int := 0; v_max_end date;
begin
  t := _tenancy_for(p_tenancy);
  for e in select * from jsonb_array_elements(p_entries) order by (value->>'date')::date loop
    n := n + 1;
    case e->>'type'
    when 'BILL' then
      insert into bill (property_id, tenancy_id, cycle_start, cycle_end, bill_date, opening_balance, status, created_by)
      values (t.property_id, t.id, coalesce((e->>'cycle_start')::date, (e->>'date')::date),
              coalesce((e->>'cycle_end')::date, (e->>'date')::date), (e->>'date')::date,
              tenancy_balance(t.id), 'DRAFT', auth.uid())
      returning id into v_bill;
      for l in select * from jsonb_array_elements(coalesce(e->'lines', '[]')) loop
        insert into bill_line (bill_id, kind, label, qty, rate, amount, meta)
        values (v_bill, coalesce((l->>'kind')::bill_line_kind, 'OTHER'), coalesce(l->>'label', 'Item'),
                (l->>'qty')::numeric, (l->>'rate')::numeric, (l->>'amount')::numeric, '{"imported":true}');
      end loop;
      perform _recalc_bill_total(v_bill);
      perform _issue(v_bill);
      v_max_end := greatest(v_max_end, (select cycle_end from bill where id = v_bill));
    when 'PAYMENT' then
      insert into payment (property_id, tenancy_id, paid_on, amount, status, note, created_by, confirmed_by, confirmed_at)
      values (t.property_id, t.id, (e->>'date')::date, (e->>'amount')::numeric, 'CONFIRMED', e->>'note',
              auth.uid(), auth.uid(), now())
      returning id into v_pay;
      insert into payment_split (payment_id, mode, amount, ref)
      values (v_pay, coalesce((e->>'mode')::payment_mode, 'CASH'), (e->>'amount')::numeric, e->>'ref');
      perform _post(t, (e->>'date')::date, 'PAYMENT', -(e->>'amount')::numeric, e->>'note', null, v_pay);
    when 'ADJUSTMENT' then
      perform _post(t, (e->>'date')::date, 'ADJUSTMENT', (e->>'amount')::numeric, coalesce(e->>'note', 'Imported'));
    when 'OPENING' then
      perform _post(t, (e->>'date')::date, 'OPENING', (e->>'amount')::numeric, coalesce(e->>'note', 'Opening balance'));
    else
      raise exception 'Unknown entry type %', e->>'type';
    end case;
  end loop;
  if v_max_end is not null then
    update tenancy set next_cycle_start = greatest(next_cycle_start, v_max_end + 1) where id = t.id;
  end if;
  perform refresh_bill_status(t.id);
  return n;
end $$;

-- ================= audit =================
create function audit_row() returns trigger language plpgsql security definer set search_path = public as $$
declare v_row jsonb := to_jsonb(coalesce(new, old));
begin
  insert into audit_log (property_id, actor, action, entity, entity_id, data)
  values ((v_row->>'property_id')::uuid, auth.uid(), tg_op, tg_table_name, v_row->>'id',
          case when tg_op = 'UPDATE' then jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new)) else v_row end);
  return coalesce(new, old);
end $$;

do $$
declare tbl text;
begin
  foreach tbl in array array['tenant', 'tenancy', 'room', 'setting', 'payment', 'charge', 'bill', 'meter_reading',
                             'ledger_entry', 'advance', 'settlement', 'notice_to_vacate', 'occupant'] loop
    execute format('create trigger audit_%1$s after insert or update or delete on %1$I
                    for each row execute function audit_row()', tbl);
  end loop;
end $$;

-- ================= views (RLS-aware) =================
create view v_tenancy_summary with (security_invoker = true) as
select tn.id as tenancy_id, tn.property_id, tn.room_id, r.number as room_number, tn.status,
       tn.start_date, tn.end_date, tn.monthly_rent, tn.next_cycle_start,
       cycle_end_of(tn.start_date, tn.next_cycle_start) as next_bill_date,
       p.id as primary_tenant_id, p.full_name as primary_name, p.phone as primary_phone,
       coalesce(l.balance, 0) as balance,
       coalesce(a.held, 0) as advance_held,
       lp.last_paid_on,
       coalesce(pc.pending_claims, 0) as pending_claims,
       nv.leave_on
from tenancy tn
join room r on r.id = tn.room_id
left join tenant p on p.id = tn.primary_tenant_id  -- left: co-occupants can't read the primary's row
left join lateral (select sum(debit) - sum(credit) as balance from ledger_entry where tenancy_id = tn.id) l on true
left join lateral (select sum(amount) as held from advance where tenancy_id = tn.id) a on true
left join lateral (select max(paid_on) as last_paid_on from payment where tenancy_id = tn.id and status = 'CONFIRMED') lp on true
left join lateral (select count(*) as pending_claims from payment where tenancy_id = tn.id and status = 'PENDING_CONFIRM') pc on true
left join lateral (select leave_on from notice_to_vacate where tenancy_id = tn.id and not withdrawn
                   order by created_at desc limit 1) nv on true;

create view v_room_board with (security_invoker = true) as
select r.id as room_id, r.property_id, r.number, r.floor, r.status as room_status, r.default_rent, r.has_meter,
       s.tenancy_id, s.status as tenancy_status, s.primary_name, s.primary_phone, s.monthly_rent,
       s.balance, s.advance_held, s.last_paid_on, s.pending_claims, s.next_bill_date, s.leave_on,
       lr.value as last_reading, lr.reading_date as last_reading_date
from room r
left join v_tenancy_summary s on s.room_id = r.id and s.status in ('ACTIVE', 'ON_NOTICE')
left join lateral (select value, reading_date from meter_reading where room_id = r.id
                   order by reading_date desc, created_at desc limit 1) lr on true;

create view v_monthly_collection with (security_invoker = true) as
select p.property_id, date_trunc('month', p.paid_on)::date as month, s.mode, sum(s.amount) as amount, count(distinct p.id) as payments
from payment p join payment_split s on s.payment_id = p.id
where p.status = 'CONFIRMED'
group by 1, 2, 3;
