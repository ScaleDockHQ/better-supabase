-- Large-tenant seed. A normal `supabase db reset` does not run this file:
-- config.toml lists only seed.sql. After a reset, load it once:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.scale.sql
--
-- It adds, on the Acme organization from seed.sql:
--   about 60,000 customers and the same number of notes;
--   149 more organizations so admin@acme.test has 150 memberships
--   (Acme is the first);
--   20 custom roles and about 300 permission keys, with a few overrides.
-- Re-running deletes the rows this file inserted, then inserts them again.

begin;

delete from public.notes
where organization_id = '00000000-0000-4000-8000-000000000001'
  and body = 'Scale note';

delete from public.customers
where organization_id = '00000000-0000-4000-8000-000000000001'
  and name like 'Scale customer %';

delete from public.memberships
where user_id = '00000000-0000-4000-8000-0000000000a1'
  and organization_id in (
    select id from public.organizations where slug like 'scale-org-%'
  );

delete from public.organizations where slug like 'scale-org-%';

delete from better_supabase.permission_overrides
where role_id in (select id from better_supabase.roles where key like 'scale_role_%');

delete from better_supabase.role_permissions
where role_id in (select id from better_supabase.roles where key like 'scale_role_%');

delete from better_supabase.permissions where key like 'scale.perm.%';

delete from better_supabase.roles where key like 'scale_role_%';

insert into public.customers (organization_id, name, status)
select
  '00000000-0000-4000-8000-000000000001',
  'Scale customer ' || i,
  case when i % 3 = 0 then 'active' else 'lead' end
from generate_series(1, 60000) as series(i);

insert into public.notes (organization_id, customer_id, kind, body)
select organization_id, id, 'call', 'Scale note'
from public.customers
where organization_id = '00000000-0000-4000-8000-000000000001'
  and name like 'Scale customer %';

insert into public.organizations (id, name, slug)
select
  ('00000000-0000-4000-8000-' || lpad(to_hex(i), 12, '0'))::uuid,
  'Scale org ' || i,
  'scale-org-' || i
from generate_series(1, 149) as series(i);

insert into public.memberships (organization_id, user_id, role)
select
  organization.id,
  '00000000-0000-4000-8000-0000000000a1',
  (select roles.id from better_supabase.roles as roles where roles.key = 'member' limit 1)
from public.organizations as organization
where organization.slug like 'scale-org-%';

insert into better_supabase.roles (key, scope)
select 'scale_role_' || i, 'tenant'
from generate_series(1, 20) as series(i);

insert into better_supabase.permissions (key)
select 'scale.perm.' || i
from generate_series(1, 300) as series(i);

insert into better_supabase.role_permissions (role_id, permission_id)
select roles.id, permissions.id
from better_supabase.roles as roles
cross join better_supabase.permissions as permissions
where roles.key like 'scale_role_%'
  and permissions.key like 'scale.perm.%'
  and (
    (substring(roles.key from '([0-9]+)$'))::integer
    = ((substring(permissions.key from '([0-9]+)$'))::integer % 20) + 1
  );

insert into better_supabase.permission_overrides (tenant_id, role_id, permission_id, granted)
select
  '00000000-0000-4000-8000-000000000001',
  roles.id,
  permissions.id,
  false
from better_supabase.roles as roles
join better_supabase.permissions as permissions
  on permissions.key = 'scale.perm.' || substring(roles.key from '([0-9]+)$')
where roles.key like 'scale_role_%';

commit;
