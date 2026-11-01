-- The invoices.send key in the fixture's permission catalog: owners and admins
-- hold it. Members don't.
insert into better_supabase.permissions (key) values ('invoices.send')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'invoices.send'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
