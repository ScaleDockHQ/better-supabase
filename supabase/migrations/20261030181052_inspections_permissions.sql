-- The inspections keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold all three; members act only on the inspections they
-- are on, through a role that grants inspections.write.
insert into better_supabase.permissions (key) values
  ('inspections.manage'), ('inspections.read'), ('inspections.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'inspections.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
