-- Record teams check `subjects.manage` to add and end a record's members.
-- Owners hold every key in the catalog; admins hold this one too.
insert into better_supabase.permissions (key) values ('subjects.manage')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'subjects.manage'
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
