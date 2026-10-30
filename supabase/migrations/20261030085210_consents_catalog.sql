-- The consents block's keys in the fixture's permission catalog: owners and
-- admins read, record and manage consent; members hold none of them.
insert into better_supabase.permissions (key) values
  ('consents.manage'), ('consents.read'), ('consents.record')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('consents.manage', 'consents.read', 'consents.record')
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
