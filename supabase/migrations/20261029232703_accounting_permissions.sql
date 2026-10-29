-- The accounting keys in the fixture's permission catalog. Owners and admins
-- keep the books; members hold none of the keys, since the books show every
-- amount the organization earns and spends.
insert into better_supabase.permissions (key) values
  ('accounting.close'), ('accounting.manage'), ('accounting.post'), ('accounting.read'),
  ('accounting.write')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'accounting.%'
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
