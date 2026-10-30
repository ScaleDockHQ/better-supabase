-- The care plans keys in the fixture's permission catalog: owners and admins
-- draft, evaluate, publish and manage plans; members read them.
insert into better_supabase.permissions (key) values
  ('care_plans.evaluate'), ('care_plans.manage'), ('care_plans.publish'),
  ('care_plans.read'), ('care_plans.write')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in (
    'care_plans.evaluate', 'care_plans.manage', 'care_plans.publish',
    'care_plans.read', 'care_plans.write'
  )
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'care_plans.read'
where r.scope = 'tenant' and r.key = 'member'
on conflict do nothing;
