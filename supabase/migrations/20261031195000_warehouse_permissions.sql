-- The warehouse keys in the fixture's permission catalog: owners and admins
-- hold all three. Members pick from the lists assigned to them.
insert into better_supabase.permissions (key) values
  ('warehouse.manage'), ('warehouse.pick'), ('warehouse.read')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'warehouse.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'warehouse.pick'
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
