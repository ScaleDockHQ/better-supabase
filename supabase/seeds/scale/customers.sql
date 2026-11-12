-- Customers {{from}} to {{to}} of the tier seed. Rows 1 to {{hot}} belong to the
-- Acme organization (the hot tenant); the rest spread over the {{tenants}} other
-- tenants. The id follows the row number, so notes find their customer without
-- a lookup and a second run skips the rows it already wrote.
insert into public.customers (id, organization_id, name, status)
select
  ('00000000-0000-4000-a000-' || lpad(to_hex(g), 12, '0'))::uuid,
  case when g <= {{hot}} then '00000000-0000-4000-8000-000000000001'::uuid
       else ('00000000-0000-4000-9000-' || lpad(to_hex((g - {{hot}} - 1) % {{tenants}} + 1), 12, '0'))::uuid end,
  'Tier customer ' || g,
  case when g % 3 = 0 then 'active' else 'lead' end
from generate_series({{from}}, {{to}}) g
on conflict do nothing
