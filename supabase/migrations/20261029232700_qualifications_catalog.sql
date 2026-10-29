-- The qualifications keys in the fixture's permission catalog: owners and
-- admins read, grant and manage qualifications; members read their own
-- holdings and gaps without a key.
insert into better_supabase.permissions (key) values
  ('qualifications.grant'), ('qualifications.manage'), ('qualifications.read')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('qualifications.grant', 'qualifications.manage', 'qualifications.read')
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
