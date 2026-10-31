-- The document template keys in the fixture's permission catalog (catalog_data):
-- owners and admins hold both; members read.
insert into better_supabase.permissions (key) values
  ('document_templates.manage'), ('document_templates.read')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'document_templates.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'document_templates.read'
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
