-- The appraisals keys in the fixture's permission catalog: owners and admins
-- hold all three. Members write their own reviews.
insert into better_supabase.permissions (key) values
  ('appraisals.manage'), ('appraisals.read'), ('appraisals.review')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key like 'appraisals.%'
where r.scope = 'tenant'
  and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p on p.key = 'appraisals.review'
where r.scope = 'tenant'
  and r.key = 'member'
on conflict do nothing;
