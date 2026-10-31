-- The till keys in the fixture's permission catalog: owners and admins hold all
-- three. Members hold none.
insert into better_supabase.permissions (key) values
  ('tills.read'), ('tills.write'), ('tills.manage')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'tills.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
