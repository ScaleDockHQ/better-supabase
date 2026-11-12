-- One note for each customer {{from}} to {{to}} of the tier seed, in the tenant
-- of the customer (see customers.sql for the rule). A second run adds the notes again.
insert into public.notes (organization_id, customer_id, kind, body)
select
  case when g <= {{hot}} then '00000000-0000-4000-8000-000000000001'::uuid
       else ('00000000-0000-4000-9000-' || lpad(to_hex((g - {{hot}} - 1) % {{tenants}} + 1), 12, '0'))::uuid end,
  ('00000000-0000-4000-a000-' || lpad(to_hex(g), 12, '0'))::uuid,
  'call',
  'Tier note ' || g
from generate_series({{from}}, {{to}}) g
