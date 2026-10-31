-- The dam keys in the fixture's permission catalog: owners and admins hold
-- both. Members hold neither.
insert into better_supabase.permissions (key) values
  ('dam.read'), ('dam.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'dam.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
