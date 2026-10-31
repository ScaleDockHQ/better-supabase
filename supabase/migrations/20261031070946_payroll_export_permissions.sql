-- The payroll-export keys in the fixture's permission catalog: owners and
-- admins hold both. Members hold neither, because a run holds everyone's hours.
insert into better_supabase.permissions (key) values
  ('payroll_export.export'), ('payroll_export.read')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'payroll\_export.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
