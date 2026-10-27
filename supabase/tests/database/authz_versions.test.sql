-- The authorization-version fixture behind `subscribeAuthzVersions`: a role,
-- membership or permission override change bumps the user's version,
-- broadcasts it on the private `authz-versions` topic, and the access token
-- hook copies it into `authz_ver` next to the active organization's
-- permission keys. User …00a1 is an admin and owns organization …0001, and
-- …00a2 is a member there, in supabase/seed.sql.
begin;
select plan(11);

create temp table seen as
select user_id, version from rbac.user_authz_versions;

create function pg_temp.bumped(member uuid)
returns bigint
language sql
as $$
  select v.version - coalesce((select s.version from seen s where s.user_id = member), 0)
  from rbac.user_authz_versions v
  where v.user_id = member
$$;

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000ff","claims":{"sub":"00000000-0000-4000-8000-0000000000ff"}}'
  ) -> 'claims' -> 'authz_ver',
  '0'::jsonb,
  'a user without a version gets authz_ver 0'
);

update rbac.user_roles
set role = role
where user_id = '00000000-0000-4000-8000-0000000000a1';

select is(
  pg_temp.bumped('00000000-0000-4000-8000-0000000000a1'),
  1::bigint,
  'a role change bumps it'
);

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1"}}'
  ) -> 'claims' -> 'authz_ver',
  to_jsonb((select version from rbac.user_authz_versions
    where user_id = '00000000-0000-4000-8000-0000000000a1')),
  'the hook copies the version into authz_ver'
);

select is(
  (select payload ->> 'user_id' from realtime.messages
   where topic = 'authz-versions' and event = 'changed' and private
   order by inserted_at desc limit 1),
  '00000000-0000-4000-8000-0000000000a1',
  'each change broadcasts the user and version on the private topic'
);

select ok(
  not has_table_privilege('authenticated', 'rbac.user_authz_versions', 'select'),
  'authenticated cannot read authorization versions'
);

update public.memberships
set role = (select id from better_supabase.roles where key = 'admin')
where organization_id = '00000000-0000-4000-8000-000000000001'
  and user_id = '00000000-0000-4000-8000-0000000000a2';

select is(
  pg_temp.bumped('00000000-0000-4000-8000-0000000000a2'),
  1::bigint,
  'a membership role change bumps the member'
);

insert into better_supabase.permission_overrides (organization_id, role_id, permission_id, granted)
select '00000000-0000-4000-8000-000000000001', r.id, p.id, false
from better_supabase.roles r, better_supabase.permissions p
where r.key = 'admin'
order by p.key
limit 1;

select is(
  pg_temp.bumped('00000000-0000-4000-8000-0000000000a2'),
  2::bigint,
  'an override bumps every member with the role in the organization'
);

select is(
  pg_temp.bumped('00000000-0000-4000-8000-0000000000a1'),
  1::bigint,
  'an override leaves members with other roles alone'
);

select is(
  jsonb_typeof(
    rbac.custom_access_token_hook(
      '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}}'
    ) -> 'claims' -> 'permissions' -> '00000000-0000-4000-8000-000000000001'
  ),
  'array',
  'the hook writes the keys for the active organization'
);

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1"}}'
  ) -> 'claims' -> 'permissions',
  '{}'::jsonb,
  'without an active organization the claim is empty'
);

select ok(
  not (
    rbac.custom_access_token_hook(
      '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}}'
    ) -> 'claims' ? 'permissions_truncated'
  ),
  'keys within the budget carry no truncated marker'
);

select * from finish();
rollback;
