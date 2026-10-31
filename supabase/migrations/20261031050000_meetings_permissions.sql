-- The meetings keys in the fixture's permission catalog: owners and admins
-- hold all three. Members read the meetings of their tenant and write on the
-- ones they chair or take minutes for, through the meeting role.
insert into better_supabase.permissions (key) values
  ('meetings.manage'), ('meetings.read'), ('meetings.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'meetings.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
