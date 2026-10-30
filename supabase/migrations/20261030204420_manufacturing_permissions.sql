-- The manufacturing keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold all four; members read and produce, so they run
-- operations and complete orders but don't change bills of materials.
insert into better_supabase.permissions (key) values
  ('manufacturing.manage'), ('manufacturing.produce'), ('manufacturing.read'), ('manufacturing.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'manufacturing.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key in ('manufacturing.read', 'manufacturing.produce')
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
