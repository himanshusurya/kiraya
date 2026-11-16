-- One building (D1). Real name/address stay out of git: set them in the owner app (Settings) or via SQL after deploy.
-- Owner logins are created with scripts/create-owner (see README).
insert into property (id, name, address, owner_name) values
  ('00000000-0000-0000-0000-000000000001', 'My PG',
   null, null)
on conflict do nothing;

insert into meter_group (id, property_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 'Meter 1 (Ground)'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001', 'Meter 2 (First floor)')
on conflict do nothing;

insert into room (property_id, number, floor, meter_group_id)
select '00000000-0000-0000-0000-000000000001'::uuid, n::text, 0, '00000000-0000-0000-0000-0000000000a1'::uuid
from generate_series(101, 108) n
union all
select '00000000-0000-0000-0000-000000000001'::uuid, n::text, 1, '00000000-0000-0000-0000-0000000000a2'::uuid
from generate_series(201, 207) n
union all
select '00000000-0000-0000-0000-000000000001'::uuid, 'Hall', 1, '00000000-0000-0000-0000-0000000000a2'::uuid
on conflict do nothing;

insert into setting (property_id, key, value, effective_from)
select '00000000-0000-0000-0000-000000000001'::uuid, k, v, date '2025-01-01'
from (values
  ('electricity_rate',    '12'::jsonb),
  ('cleaning_charge',     '500'),
  ('notice_period_days',  '30'),
  ('default_advance',     '3000'),
  ('meter_reading_day',   '1'),
  ('due_after_bill_days', '5'),
  ('grace_days',          '0'),
  ('late_fee',            '0'),
  ('auto_issue',          'false'),
  ('language_default',    '"en"'),
  ('upi_id',              '""'),
  ('upi_name',            '""'),
  ('owner_phone',         '""'),
  ('reminder_en', '"Hello {name}, your rent for room {room} is due: ₹{due}. Please pay soon. Thank you."'),
  ('reminder_hi', '"नमस्ते {name}, रूम {room} का किराया बाकी है: ₹{due}। कृपया जल्दी जमा करें। धन्यवाद।"')
) s(k, v)
on conflict do nothing;
