-- The permission keys the Phase 5 admin pages read. The library's modules add the keys to the
-- catalog but not to the example's roles, so owners and admins hold them here. Admins also hold
-- numbering.assign, which gates the numbering page (the block has no read key).
insert into better_supabase.permissions (key) values
  ('domains.read'), ('domains.manage'), ('option_sets.read'), ('option_sets.manage'),
  ('numbering.assign'), ('flags.manage')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('domains.read', 'domains.manage', 'option_sets.read', 'option_sets.manage', 'numbering.assign')
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;

-- Platform staff: flags.manage is a platform permission, so a platform role carries it and
-- the example's admin user holds that role.
insert into better_supabase.roles (key, scope)
values ('platform_admin', 'platform')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'flags.manage'
where r.key = 'platform_admin'
on conflict do nothing;

insert into better_supabase.platform_roles (user_id, role_id)
select u.id, r.id
from auth.users u
join better_supabase.roles r on r.key = 'platform_admin'
where u.email = 'admin@acme.test'
on conflict do nothing;
