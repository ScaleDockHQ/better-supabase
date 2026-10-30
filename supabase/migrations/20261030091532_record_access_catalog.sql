-- Emergency access checks `access_requests.emergency` to open and
-- `access_requests.review` to review. Owners hold every key in the catalog;
-- admins hold `access_requests.*`, so both. Members hold neither.
insert into better_supabase.permissions (key) values
  ('access_requests.emergency'),
  ('access_requests.review')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('access_requests.emergency', 'access_requests.review')
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;
