-- Restricted progress notes check `activities.read_restricted`. Owners hold
-- every key in the catalog; admins hold `activities.*` in the default roles.
insert into better_supabase.permissions (key) values ('activities.read_restricted')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'activities.read_restricted'
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
