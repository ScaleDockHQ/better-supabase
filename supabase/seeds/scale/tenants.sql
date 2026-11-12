-- Tenants {{from}} to {{to}} of the tier seed, next to the Acme organization.
-- Ids and slugs are fixed, so a second run skips the rows it already wrote.
insert into public.organizations (id, name, slug)
select
  ('00000000-0000-4000-9000-' || lpad(to_hex(g), 12, '0'))::uuid,
  'Scale tenant ' || g,
  'scale-tenant-' || g
from generate_series({{from}}, {{to}}) g
on conflict do nothing
