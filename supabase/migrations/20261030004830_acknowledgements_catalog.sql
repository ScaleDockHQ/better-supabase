-- The acknowledgements keys in the fixture's permission catalog: owners and
-- admins assign and read acknowledgements, members acknowledge what they are
-- asked to read. Same split as the roles list in the permissions module.
insert into better_supabase.permissions (key) values
  ('acknowledgements.acknowledge'), ('acknowledgements.manage'), ('acknowledgements.read')
on conflict (key) do nothing;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r
join lateral unnest(case r.key
  when 'owner' then array['acknowledgements.acknowledge', 'acknowledgements.manage', 'acknowledgements.read']
  when 'admin' then array['acknowledgements.acknowledge', 'acknowledgements.manage', 'acknowledgements.read']
  when 'member' then array['acknowledgements.acknowledge']
end) as k(key) on true
join better_supabase.permissions p on p.key = k.key
where r.scope = 'tenant'
on conflict do nothing;
