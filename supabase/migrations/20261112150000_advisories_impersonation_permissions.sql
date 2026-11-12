-- The advisories and impersonation keys in the fixture's permission catalog:
-- owners and admins hold all of them, members read advisories. Support sessions
-- still need is_platform() and a second admin's approval, whatever the keys say.
insert into better_supabase.permissions (key) values
  ('advisories.read'), ('advisories.write'), ('advisories.publish'),
  ('impersonation.read'), ('impersonation.start'), ('impersonation.revoke')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'advisories.%' or p.key like 'impersonation.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'advisories.read'
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;

select better_supabase.bump_authz_versions(array(select id from auth.users))
where to_regprocedure('better_supabase.bump_authz_versions(uuid[])') is not null;
