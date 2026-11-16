-- Ghar Kiraya / Tenant Management – core schema (HLD v0.4 §6)
-- Money: numeric(12,2) rupees. Dates: Asia/Kolkata calendar dates.

-- ---------- enums ----------
create type app_role        as enum ('OWNER', 'TENANT');
create type room_status     as enum ('VACANT', 'OCCUPIED', 'OWNER_USE', 'MAINTENANCE');
create type reading_kind    as enum ('MONTHLY', 'MOVE_IN', 'MOVE_OUT', 'SHIFT');
create type tenancy_status  as enum ('ACTIVE', 'ON_NOTICE', 'CLOSED', 'ABSCONDED', 'SHIFTED');
create type charge_kind     as enum ('RECURRING', 'ONE_OFF');
create type bill_status     as enum ('DRAFT', 'ISSUED', 'PARTIAL', 'PAID');
create type bill_line_kind  as enum ('RENT', 'ELECTRICITY', 'CHARGE', 'LATE_FEE', 'CLEANING', 'NOTICE_SHORTFALL', 'OTHER');
create type payment_status  as enum ('CONFIRMED', 'PENDING_CONFIRM', 'REJECTED', 'VOID');
create type payment_mode    as enum ('CASH', 'PHONEPE', 'GPAY', 'UPI_OTHER', 'BANK');
create type ledger_kind     as enum ('OPENING', 'BILL', 'PAYMENT', 'PAYMENT_VOID', 'ADJUSTMENT', 'ADVANCE_ADJ', 'REFUND', 'WRITE_OFF', 'TRANSFER');
create type complaint_status as enum ('OPEN', 'IN_PROGRESS', 'RESOLVED');
create type settlement_outcome as enum ('REFUNDED', 'SETTLED', 'DUE_PENDING', 'WRITTEN_OFF');

-- ---------- property & users ----------
create table property (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  address     text,
  owner_name  text,
  created_at  timestamptz not null default now()
);

create table app_user (
  id          uuid primary key,                -- = auth.users.id
  property_id uuid not null references property(id),
  role        app_role not null,
  name        text not null,
  phone       text,
  tenant_id   uuid,                            -- set for TENANT logins (FK added below)
  language    text not null default 'en' check (language in ('en', 'hi')),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  check (role = 'OWNER' or tenant_id is not null)
);

-- Versioned settings: the row with the latest effective_from <= date wins.
create table setting (
  id             bigint generated always as identity primary key,
  property_id    uuid not null references property(id),
  key            text not null,
  value          jsonb not null,
  effective_from date not null default current_date,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  unique (property_id, key, effective_from)
);

-- ---------- building ----------
create table meter_group (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references property(id),
  name        text not null,
  unique (property_id, name)
);

create table room (
  id             uuid primary key default gen_random_uuid(),
  property_id    uuid not null references property(id),
  number         text not null,
  floor          int,
  meter_group_id uuid references meter_group(id),
  has_meter      boolean not null default true,
  default_rent   numeric(12,2),
  status         room_status not null default 'VACANT',
  notes          text,
  unique (property_id, number)
);

create table meter_reading (
  id             uuid primary key default gen_random_uuid(),
  property_id    uuid not null references property(id),
  room_id        uuid not null references room(id),
  reading_date   date not null,
  value          numeric(12,1) not null check (value >= 0),
  kind           reading_kind not null default 'MONTHLY',
  billed_bill_id uuid,                         -- FK added below
  note           text,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  unique (room_id, reading_date, kind)
);
create index on meter_reading (room_id, reading_date);

-- ---------- people ----------
-- Fields mirror the paper renter form (kept as-is per D14).
create table tenant (
  id                 uuid primary key default gen_random_uuid(),
  property_id        uuid not null references property(id),
  full_name          text not null,
  father_name        text,
  dob                date,
  age                int,
  gender             text,
  phone              text,
  alt_phone          text,
  email              text,
  occupation         text,
  workplace          text,
  caste              text,
  religion           text,
  permanent_address  text,
  native_police_station text,
  id_type            text,
  id_number          text,
  vehicle_number     text,
  emergency_name     text,
  emergency_phone    text,
  photo_path         text,
  extra              jsonb not null default '{}'::jsonb,
  notes              text,
  created_at         timestamptz not null default now()
);
create index on tenant (property_id, phone);

alter table app_user add constraint app_user_tenant_fk foreign key (tenant_id) references tenant(id);

create table kyc_document (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references tenant(id) on delete cascade,
  kind         text not null,                 -- AADHAAR / PAN / DL / PHOTO / OTHER
  storage_path text not null,
  uploaded_by  uuid,
  created_at   timestamptz not null default now()
);

-- ---------- tenancy ----------
create table tenancy (
  id                   uuid primary key default gen_random_uuid(),
  property_id          uuid not null references property(id),
  room_id              uuid not null references room(id),
  primary_tenant_id    uuid not null references tenant(id),
  start_date           date not null,          -- rent-cycle anchor (D3)
  end_date             date,
  monthly_rent         numeric(12,2) not null check (monthly_rent >= 0),
  status               tenancy_status not null default 'ACTIVE',
  next_cycle_start     date not null,          -- first not-yet-billed day
  elec_last_reading_id uuid references meter_reading(id),  -- last reading already charged / baseline
  due_after_days       int,                    -- per-tenant overrides (null = use setting)
  grace_days           int,
  late_fee             numeric(12,2),
  previous_tenancy_id  uuid references tenancy(id),        -- set on room shift
  notes                text,
  created_at           timestamptz not null default now()
);
create unique index one_live_tenancy_per_room on tenancy (room_id) where status in ('ACTIVE', 'ON_NOTICE');

create table occupant (
  id          uuid primary key default gen_random_uuid(),
  tenancy_id  uuid not null references tenancy(id) on delete cascade,
  tenant_id   uuid not null references tenant(id),
  is_primary  boolean not null default false,
  app_access  boolean not null default false,
  joined_on   date not null,
  left_on     date,
  unique (tenancy_id, tenant_id)
);

-- Advance (security deposit) is held money, not a due; it is kept off the ledger
-- until it is used at move-out (ADVANCE_ADJ) or refunded.
create table advance (
  id          uuid primary key default gen_random_uuid(),
  tenancy_id  uuid not null references tenancy(id),
  amount      numeric(12,2) not null,          -- negative rows = used/refunded/transferred out
  txn_date    date not null,
  note        text,
  created_by  uuid,
  created_at  timestamptz not null default now()
);

create table charge (
  id             uuid primary key default gen_random_uuid(),
  tenancy_id     uuid not null references tenancy(id),
  label          text not null,
  amount         numeric(12,2) not null,       -- may be negative (discount)
  kind           charge_kind not null,
  start_date     date not null,                -- ONE_OFF: the date it applies
  end_date       date,                         -- RECURRING: optional stop date
  billed_bill_id uuid,                         -- ONE_OFF: bill that charged it
  active         boolean not null default true,
  created_by     uuid,
  created_at     timestamptz not null default now()
);

-- ---------- bills ----------
create table bill (
  id                    uuid primary key default gen_random_uuid(),
  bill_no               bigint generated always as identity,
  property_id           uuid not null references property(id),
  tenancy_id            uuid not null references tenancy(id),
  cycle_start           date not null,
  cycle_end             date not null,
  bill_date             date not null,
  due_date              date,
  opening_balance       numeric(12,2) not null default 0,
  total                 numeric(12,2) not null default 0,
  status                bill_status not null default 'DRAFT',
  is_final              boolean not null default false,
  prev_elec_reading_id  uuid,                  -- for discarding a draft
  issued_at             timestamptz,
  created_by            uuid,
  created_at            timestamptz not null default now()
);
create index on bill (tenancy_id, cycle_start);

alter table meter_reading add constraint meter_reading_bill_fk foreign key (billed_bill_id) references bill(id) on delete set null;
alter table charge add constraint charge_bill_fk foreign key (billed_bill_id) references bill(id) on delete set null;

create table bill_line (
  id       uuid primary key default gen_random_uuid(),
  bill_id  uuid not null references bill(id) on delete cascade,
  kind     bill_line_kind not null,
  label    text not null,
  qty      numeric(12,2),
  rate     numeric(12,2),
  amount   numeric(12,2) not null,
  meta     jsonb not null default '{}'::jsonb,
  sort     int not null default 0
);

-- ---------- payments (recorded, no gateway – D7) ----------
create table payment (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references property(id),
  tenancy_id      uuid not null references tenancy(id),
  paid_on         date not null,
  amount          numeric(12,2) not null check (amount > 0),
  status          payment_status not null,
  claimed_by_tenant boolean not null default false,
  note            text,
  proof_path      text,
  reject_reason   text,
  idempotency_key text unique,
  created_by      uuid,
  confirmed_by    uuid,
  confirmed_at    timestamptz,
  created_at      timestamptz not null default now()
);
create index on payment (tenancy_id, paid_on);

create table payment_split (
  id         uuid primary key default gen_random_uuid(),
  payment_id uuid not null references payment(id) on delete cascade,
  mode       payment_mode not null,
  amount     numeric(12,2) not null check (amount > 0),
  ref        text
);

-- ---------- ledger (append-only) ----------
create table ledger_entry (
  id          bigint generated always as identity primary key,
  property_id uuid not null references property(id),
  tenancy_id  uuid not null references tenancy(id),
  entry_date  date not null,
  kind        ledger_kind not null,
  debit       numeric(12,2) not null default 0 check (debit >= 0),
  credit      numeric(12,2) not null default 0 check (credit >= 0),
  bill_id     uuid references bill(id),
  payment_id  uuid references payment(id),
  note        text,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  check (debit > 0 or credit > 0)
);
create index on ledger_entry (tenancy_id, entry_date, id);

create function ledger_is_append_only() returns trigger language plpgsql as $$
begin
  raise exception 'ledger_entry is append-only; post an ADJUSTMENT instead';
end $$;
create trigger ledger_no_update before update or delete on ledger_entry
  for each row execute function ledger_is_append_only();

-- ---------- move-out ----------
create table notice_to_vacate (
  id            uuid primary key default gen_random_uuid(),
  tenancy_id    uuid not null references tenancy(id),
  given_on      date not null,
  leave_on      date not null,
  given_by_tenant boolean not null default false,
  withdrawn     boolean not null default false,
  note          text,
  created_by    uuid,
  created_at    timestamptz not null default now()
);

create table settlement (
  id               uuid primary key default gen_random_uuid(),
  tenancy_id       uuid not null unique references tenancy(id),
  leave_date       date not null,
  final_bill_id    uuid references bill(id),
  advance_held     numeric(12,2) not null,
  advance_applied  numeric(12,2) not null,
  refund_amount    numeric(12,2) not null,
  written_off      numeric(12,2) not null default 0,
  balance_after    numeric(12,2) not null,
  outcome          settlement_outcome not null,
  note             text,
  created_by       uuid,
  created_at       timestamptz not null default now()
);

-- ---------- communication ----------
create table complaint (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references property(id),
  tenancy_id  uuid references tenancy(id),
  room_id     uuid references room(id),
  category    text not null default 'OTHER',  -- WATER / LIGHT / CLEANING / REPAIR / OTHER
  text        text not null,
  photo_path  text,
  status      complaint_status not null default 'OPEN',
  owner_note  text,
  raised_by   uuid,
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);

create table notice (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references property(id),
  title       text not null,
  body        text not null,
  room_id     uuid references room(id),        -- null = everyone
  created_by  uuid,
  created_at  timestamptz not null default now()
);

create table device_token (
  user_id    uuid not null,
  token      text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create table audit_log (
  id          bigint generated always as identity primary key,
  property_id uuid,
  actor       uuid,
  action      text not null,
  entity      text not null,
  entity_id   text,
  data        jsonb,
  created_at  timestamptz not null default now()
);
