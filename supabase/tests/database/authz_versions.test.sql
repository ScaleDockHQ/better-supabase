-- The authorization-version fixture behind `subscribeAuthzVersions`: a role
-- change bumps the user's version, broadcasts it on the private
-- `authz-versions` topic, and the access token hook copies it into
-- `authz_ver`. User …00a1 is an admin in supabase/seed.sql.
begin;
select plan(6);

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000ff","claims":{"sub":"00000000-0000-4000-8000-0000000000ff"}}'
  ) -> 'claims' -> 'authz_ver',
  '0'::jsonb,
  'a user without a version gets authz_ver 0'
);

select is(
  (select version from rbac.user_authz_versions
   where user_id = '00000000-0000-4000-8000-0000000000a1'),
  1::bigint,
  'seeding the role stored version 1'
);

update rbac.user_roles
set role = role
where user_id = '00000000-0000-4000-8000-0000000000a1';

select is(
  (select version from rbac.user_authz_versions
   where user_id = '00000000-0000-4000-8000-0000000000a1'),
  2::bigint,
  'a role change bumps it'
);

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1"}}'
  ) -> 'claims' -> 'authz_ver',
  '2'::jsonb,
  'the hook copies the version into authz_ver'
);

select is(
  (select payload - 'id' from realtime.messages
   where topic = 'authz-versions' and event = 'changed' and private
   order by inserted_at desc limit 1),
  '{"user_id":"00000000-0000-4000-8000-0000000000a1","version":2}'::jsonb,
  'each change broadcasts the user and version on the private topic'
);

select ok(
  not has_table_privilege('authenticated', 'rbac.user_authz_versions', 'select'),
  'authenticated cannot read authorization versions'
);

select * from finish();
rollback;
