-- The supplier approval key in the fixture's permission catalog: owners and
-- admins set a company's or person's supplier status; members edit records
-- but can't approve them as suppliers.
insert into better_supabase.permissions (key) values ('contacts.approve_supplier')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'contacts.approve_supplier'
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
