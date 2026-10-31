-- The banking keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold all four; members read the accounts and reconcile,
-- but don't import statements or change accounts and rules.
insert into better_supabase.permissions (key) values
  ('banking.import'), ('banking.manage'), ('banking.read'), ('banking.reconcile')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'banking.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key in ('banking.read', 'banking.reconcile')
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
