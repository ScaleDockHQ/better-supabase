-- The keys of the reviews, collections, warranty and agent-checkout blocks in the
-- fixture's permission catalog: owners and admins hold all of them, members read
-- claims, collections and checkout sessions and may file warranty claims.
insert into better_supabase.permissions (key) values
  ('reviews.manage'),
  ('collections.read'), ('collections.write'), ('collections.share'),
  ('warranty.read'), ('warranty.write'), ('warranty.decide'),
  ('agent_checkout.read'), ('agent_checkout.write'), ('agent_checkout.manage')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key = 'reviews.manage'
  or p.key like 'collections.%'
  or p.key like 'warranty.%'
  or p.key like 'agent_checkout.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in (
    'collections.read', 'collections.write', 'warranty.read', 'warranty.write',
    'agent_checkout.read'
  )
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
