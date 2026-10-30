-- The risks keys in the fixture's permission catalog (catalog_data): owners
-- and admins hold all four, members read the register.
insert into better_supabase.permissions (key) values
  ('risks.assess'), ('risks.manage'), ('risks.read'), ('risks.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'risks.%'
where r.scope = 'tenant'
  and (r.key in ('owner', 'admin') or (r.key = 'member' and p.key = 'risks.read'))
on conflict do nothing;
