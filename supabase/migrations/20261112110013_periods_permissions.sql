-- The periods keys in the fixture's permission catalog: owners and admins hold
-- both, members read periods. The finance pages list periods behind periods.read.
insert into better_supabase.permissions (key) values
  ('periods.manage'), ('periods.read'), ('periods.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'periods.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'periods.read'
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
