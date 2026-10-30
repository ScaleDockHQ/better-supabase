-- The medications keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold all four, members none.
insert into better_supabase.permissions (key) values
  ('medications.administer'), ('medications.manage'), ('medications.prescribe'),
  ('medications.read')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'medications.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
