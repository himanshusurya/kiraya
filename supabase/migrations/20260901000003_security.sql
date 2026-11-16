-- Row Level Security & grants (HLD v0.4 §12)
-- OWNER: everything in their property. TENANT: only rows of tenancies they occupy.
-- Money tables are read-only for clients; writes go through the RPCs in *_logic.sql.

do $$
declare tbl text;
begin
  foreach tbl in array array['property', 'app_user', 'setting', 'meter_group', 'room', 'meter_reading', 'tenant',
    'kyc_document', 'tenancy', 'occupant', 'advance', 'charge', 'bill', 'bill_line', 'payment', 'payment_split',
    'ledger_entry', 'notice_to_vacate', 'settlement', 'complaint', 'notice', 'device_token', 'audit_log'] loop
    execute format('alter table %I enable row level security', tbl);
    execute format('revoke all on %I from anon, authenticated', tbl);
    execute format('grant select on %I to authenticated', tbl);
  end loop;
end $$;

revoke all on v_tenancy_summary, v_room_board, v_monthly_collection from anon, authenticated;
grant select on v_tenancy_summary, v_room_board, v_monthly_collection to authenticated;

-- helper: is the caller the owner of this tenancy's property?
create function owns_tenancy(p_tenancy uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_owner() and exists (select 1 from tenancy where id = p_tenancy and property_id = my_property_id())
$$;

-- ---------- owner-wide read policies ----------
create policy owner_all on property for select using (id = my_property_id());
create policy self_or_owner on app_user for select using (id = auth.uid() or (is_owner() and property_id = my_property_id()));

create policy owner_read on setting       for select using (is_owner() and property_id = my_property_id());
create policy owner_read on meter_group   for select using (property_id = my_property_id());
create policy owner_read on room          for select using (is_owner() and property_id = my_property_id());
create policy owner_read on meter_reading for select using (is_owner() and property_id = my_property_id());
create policy owner_read on tenant        for select using (is_owner() and property_id = my_property_id());
create policy owner_read on tenancy       for select using (is_owner() and property_id = my_property_id());
create policy owner_read on bill          for select using (is_owner() and property_id = my_property_id());
create policy owner_read on payment       for select using (is_owner() and property_id = my_property_id());
create policy owner_read on ledger_entry  for select using (is_owner() and property_id = my_property_id());
create policy owner_read on complaint     for select using (is_owner() and property_id = my_property_id());
create policy owner_read on notice        for select using (is_owner() and property_id = my_property_id());
create policy owner_read on audit_log     for select using (is_owner() and property_id = my_property_id());

create policy owner_read on occupant         for select using (owns_tenancy(tenancy_id));
create policy owner_read on advance          for select using (owns_tenancy(tenancy_id));
create policy owner_read on charge           for select using (owns_tenancy(tenancy_id));
create policy owner_read on notice_to_vacate for select using (owns_tenancy(tenancy_id));
create policy owner_read on settlement       for select using (owns_tenancy(tenancy_id));
create policy owner_read on bill_line        for select using (exists (select 1 from bill b where b.id = bill_id and owns_tenancy(b.tenancy_id)));
create policy owner_read on payment_split    for select using (exists (select 1 from payment p where p.id = payment_id and owns_tenancy(p.tenancy_id)));
create policy owner_read on kyc_document     for select using (is_owner() and exists (select 1 from tenant t where t.id = tenant_id and t.property_id = my_property_id()));

-- ---------- tenant read policies ----------
create policy tenant_read on room          for select using (id in (select my_room_ids()));
create policy tenant_read on tenancy       for select using (id in (select my_tenancy_ids()));
create policy tenant_read on tenant        for select using (id = my_tenant_id());
create policy tenant_read on occupant      for select using (tenant_id = my_tenant_id());
create policy tenant_read on advance       for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on charge        for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on bill          for select using (tenancy_id in (select my_tenancy_ids()) and status <> 'DRAFT');
create policy tenant_read on bill_line     for select using (exists (select 1 from bill b where b.id = bill_id and b.status <> 'DRAFT' and b.tenancy_id in (select my_tenancy_ids())));
create policy tenant_read on payment       for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on payment_split for select using (exists (select 1 from payment p where p.id = payment_id and p.tenancy_id in (select my_tenancy_ids())));
create policy tenant_read on ledger_entry  for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on notice_to_vacate for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on settlement    for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on complaint     for select using (tenancy_id in (select my_tenancy_ids()));
create policy tenant_read on notice        for select using (property_id = my_property_id() and (room_id is null or room_id in (select my_room_ids())));
create policy tenant_read on kyc_document  for select using (tenant_id = my_tenant_id());
create policy tenant_read on meter_reading for select using (
  exists (select 1 from tenancy t where t.id in (select my_tenancy_ids()) and t.room_id = meter_reading.room_id
          and meter_reading.reading_date >= t.start_date and (t.end_date is null or meter_reading.reading_date <= t.end_date)));

-- ---------- direct writes (non-money) ----------
grant insert, update on room to authenticated;
create policy owner_write on room for insert with check (is_owner() and property_id = my_property_id());
create policy owner_update on room for update using (is_owner() and property_id = my_property_id());

grant insert, update on tenant to authenticated;
create policy owner_write on tenant for insert with check (is_owner() and property_id = my_property_id());
create policy owner_update on tenant for update using (is_owner() and property_id = my_property_id());

grant update (monthly_rent, due_after_days, grace_days, late_fee, notes) on tenancy to authenticated;
create policy owner_update on tenancy for update using (is_owner() and property_id = my_property_id());

grant insert, update on complaint to authenticated;
create policy owner_write on complaint for insert with check (is_owner() and property_id = my_property_id());
create policy owner_update on complaint for update using (is_owner() and property_id = my_property_id());
create policy tenant_write on complaint for insert with check (
  property_id = my_property_id() and tenancy_id in (select my_tenancy_ids()) and raised_by = auth.uid() and status = 'OPEN');

grant insert, delete on notice to authenticated;
create policy owner_write on notice for insert with check (is_owner() and property_id = my_property_id());
create policy owner_delete on notice for delete using (is_owner() and property_id = my_property_id());

grant insert, delete on kyc_document to authenticated;
create policy owner_write on kyc_document for insert with check (is_owner() and exists (select 1 from tenant t where t.id = tenant_id and t.property_id = my_property_id()));
create policy owner_delete on kyc_document for delete using (is_owner() and exists (select 1 from tenant t where t.id = tenant_id and t.property_id = my_property_id()));
create policy tenant_write on kyc_document for insert with check (tenant_id = my_tenant_id());

grant insert on meter_group to authenticated;
create policy owner_write on meter_group for insert with check (is_owner() and property_id = my_property_id());

grant insert, delete on device_token to authenticated;
create policy own_tokens on device_token for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- functions ----------
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  today_ist(), is_service(), my_property_id(), is_owner(), my_tenant_id(), my_tenancy_ids(), my_room_ids(),
  owns_tenancy(uuid), cycle_end_of(date, date), tenancy_balance(uuid), advance_held(uuid),
  setting_value(uuid, text, date), setting_num(uuid, text, date, numeric),
  generate_due_bills(date), issue_bill(uuid), issue_all_drafts(), add_bill_line(uuid, text, numeric),
  remove_bill_line(uuid), discard_draft_bill(uuid),
  add_readings(date, jsonb, reading_kind, boolean), onboard_tenant(jsonb), add_occupant(uuid, jsonb, date),
  remove_occupant(uuid, uuid, date), add_charge(uuid, text, numeric, charge_kind, date, date), stop_charge(uuid, date),
  adjust(uuid, numeric, text, date), record_payment(uuid, date, jsonb, text, text),
  claim_payment(uuid, date, numeric, payment_mode, text, text, text, text), confirm_payment(uuid, boolean, text),
  void_payment(uuid, text), give_notice(uuid, date, date, text), withdraw_notice(uuid),
  settle_move_out(uuid, date, numeric, numeric, numeric, jsonb, boolean, boolean, text),
  shift_room(uuid, uuid, date, numeric, numeric, numeric), update_setting(text, jsonb, date),
  current_settings(), set_my_language(text), set_app_access(uuid, uuid, boolean), import_history(uuid, jsonb)
to authenticated;

grant execute on function cron_daily(date) to service_role;

-- ---------- storage: KYC images & payment screenshots (private bucket) ----------
-- Path convention: kyc/<tenant_id>/<file>, proof/<tenancy_id>/<file>
insert into storage.buckets (id, name, public) values ('private', 'private', false) on conflict do nothing;

create policy owner_files on storage.objects for all to authenticated
  using (bucket_id = 'private' and is_owner())
  with check (bucket_id = 'private' and is_owner());

create policy tenant_kyc_files on storage.objects for all to authenticated
  using (bucket_id = 'private' and (storage.foldername(name))[1] = 'kyc'
         and (storage.foldername(name))[2] = my_tenant_id()::text)
  with check (bucket_id = 'private' and (storage.foldername(name))[1] = 'kyc'
              and (storage.foldername(name))[2] = my_tenant_id()::text);

create policy tenant_proof_files on storage.objects for all to authenticated
  using (bucket_id = 'private' and (storage.foldername(name))[1] = 'proof'
         and (storage.foldername(name))[2]::uuid in (select my_tenancy_ids()))
  with check (bucket_id = 'private' and (storage.foldername(name))[1] = 'proof'
              and (storage.foldername(name))[2]::uuid in (select my_tenancy_ids()));
