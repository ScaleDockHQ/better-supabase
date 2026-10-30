-- The cases keys in the fixture's permission catalog (catalog_data): owners
-- and admins hold all five, members read cases and open them.
insert into better_supabase.permissions (key) values
  ('cases.close'), ('cases.create'), ('cases.manage'), ('cases.read'), ('cases.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'cases.%'
where r.scope = 'tenant'
  and (
    r.key in ('owner', 'admin')
    or (r.key = 'member' and p.key in ('cases.read', 'cases.create'))
  )
on conflict do nothing;
