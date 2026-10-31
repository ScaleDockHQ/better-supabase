-- The funding keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold all six; members read and register care, so they
-- record deliveries but don't approve, claim or change awards.
insert into better_supabase.permissions (key) values
  ('funding.approve'), ('funding.claim'), ('funding.manage'), ('funding.read'),
  ('funding.register'), ('funding.write')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'funding.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key in ('funding.read', 'funding.register')
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
