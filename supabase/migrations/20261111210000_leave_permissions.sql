-- The leave keys in the fixture's permission catalog: owners and admins hold
-- all four, members request leave and see their own.
-- The deadlines keys were never registered in the fixture either: owners and
-- admins hold all three, members read.
insert into better_supabase.permissions (key) values
  ('leave.request'), ('leave.read'), ('leave.approve'), ('leave.manage'),
  ('deadlines.read'), ('deadlines.write'), ('deadlines.manage')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'leave.%' or p.key like 'deadlines.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key in ('leave.request', 'deadlines.read')
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;

select better_supabase.bump_authz_versions(array(select id from auth.users))
where to_regprocedure('better_supabase.bump_authz_versions(uuid[])') is not null;
