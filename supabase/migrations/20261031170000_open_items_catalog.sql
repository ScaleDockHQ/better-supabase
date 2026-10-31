-- The approval key in the fixture's permission catalog: owners and admins
-- approve purchase bills; members don't.
insert into better_supabase.permissions (key)
values ('invoices.approve')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'invoices.approve'
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
