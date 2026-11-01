-- The clinical decision support keys in the fixture's permission catalog: owners and admins hold all
-- three. Members hold none.
insert into better_supabase.permissions (key) values
  ('clinical_decision_support.read'), ('clinical_decision_support.write'), ('clinical_decision_support.manage')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'clinical_decision_support.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;
