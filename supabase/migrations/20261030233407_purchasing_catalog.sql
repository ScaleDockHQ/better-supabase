-- The purchasing keys in the fixture's permission catalog: owners and admins
-- write purchase bills, pay a bill that fails its three-way match and place an
-- order or issue an invoice over a party's credit limit; members don't.
insert into better_supabase.permissions (key)
values ('invoices.purchase'), ('invoices.override_match'), ('orders.override_credit')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('invoices.purchase', 'invoices.override_match', 'orders.override_credit')
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
