-- The shifts keys in the fixture's permission catalog: owners and admins plan,
-- publish and decide; members read the published roster and ask for open
-- shifts and swaps.
insert into better_supabase.permissions (key) values
  ('shifts.manage'), ('shifts.read'), ('shifts.request'), ('shifts.write')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('shifts.manage', 'shifts.read', 'shifts.request', 'shifts.write')
where r.scope = 'tenant' and r.key in ('owner', 'admin')
on conflict do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join better_supabase.permissions p
  on p.key in ('shifts.read', 'shifts.request')
where r.scope = 'tenant' and r.key = 'member'
on conflict do nothing;
