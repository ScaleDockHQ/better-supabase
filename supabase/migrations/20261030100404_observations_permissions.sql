-- The observations keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold all three, members read and record observations.
insert into better_supabase.permissions (key) values
  ('observations.manage'), ('observations.read'), ('observations.record')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'observations.%'
where r.scope = 'tenant'
  and (r.key in ('owner', 'admin')
    or (r.key = 'member' and p.key in ('observations.read', 'observations.record')))
on conflict do nothing;
