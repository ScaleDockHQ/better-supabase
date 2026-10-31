-- The legal entity keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold both; members read.
insert into better_supabase.permissions (key) values
  ('legal_entities.manage'), ('legal_entities.read')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'legal_entities.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'legal_entities.read'
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
