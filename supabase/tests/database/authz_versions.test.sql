-- The sessions module's authorization versions (options.authzVersions): a
-- role, membership or permission override change bumps the user's version,
-- broadcasts it on the private `better_supabase:authz` topic and on the
-- user's own `authz:<uid>`, and the access token hook copies it into
-- `authz_ver` next to the active organization's permission keys. User …00a1 is an admin and owns organization …0001, and
-- …00a2 is a member there, in supabase/seed.sql.
begin;
select plan(17);

create temp table seen as
select user_id, version from better_supabase.user_authz_versions;

create function pg_temp.bumped(member uuid)
returns bigint
language sql
as $$
  select v.version - coalesce((select s.version from seen s where s.user_id = member), 0)
  from better_supabase.user_authz_versions v
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
  to_jsonb((select version from better_supabase.user_authz_versions
    where user_id = '00000000-0000-4000-8000-0000000000a1')),
  'the hook copies the version into authz_ver'
);

select is(
  (select payload ->> 'user_id' from realtime.messages
   where topic = 'better_supabase:authz' and event = 'changed' and private
   order by inserted_at desc limit 1),
  '00000000-0000-4000-8000-0000000000a1',
  'each change broadcasts the user and version on the server topic'
);

select ok(
  exists (select 1 from realtime.messages
   where topic = 'authz:00000000-0000-4000-8000-0000000000a1'
     and event = 'changed' and private),
  'and on the user''s own topic'
);

select ok(
  exists (select 1 from pg_policies
   where schemaname = 'realtime' and tablename = 'messages'
     and policyname = 'bsb_authz_versions_receive'),
  'a user may receive their own authz topic'
);

select ok(
  not has_table_privilege('authenticated', 'better_supabase.user_authz_versions', 'select'),
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

insert into better_supabase.permission_overrides (tenant_id, role_id, permission_id, granted)
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

-- A role's catalog grants change outside the API, as a migration does (EX-808).
-- The trigger on role_permissions bumps every member who holds the role, so
-- each open session refreshes its token and sees the new key.
create temp table before_grant as
select user_id, version from better_supabase.user_authz_versions;

insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id
from better_supabase.roles r, better_supabase.permissions p
where r.key = 'admin' and p.key = 'flags.manage'
on conflict do nothing;

select ok(
  (select v.version > coalesce(b.version, 0)
   from better_supabase.user_authz_versions v
   left join before_grant b on b.user_id = v.user_id
   where v.user_id = '00000000-0000-4000-8000-0000000000a2'),
  'a role grant added by a migration bumps the members who hold the role'
);

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000a2","claims":{"sub":"00000000-0000-4000-8000-0000000000a2"}}'
  ) -> 'claims' -> 'authz_ver',
  to_jsonb((select version from better_supabase.user_authz_versions
    where user_id = '00000000-0000-4000-8000-0000000000a2')),
  'the next token carries the bumped version'
);

select ok(
  'flags.manage' = any (
    array(select jsonb_array_elements_text(
      better_supabase.permission_claims(
        '00000000-0000-4000-8000-0000000000a2',
        '00000000-0000-4000-8000-000000000001'
      ) -> '00000000-0000-4000-8000-000000000001'
    ))
  ),
  'and the keys behind that token include the new grant'
);

-- Every block adds permissions, so the full owner set no longer fits the hook's
-- 2048 byte budget. Trim the owner role to the first half of the alphabet so the
-- next two assertions test a set that fits.
delete from better_supabase.role_permissions rp
using better_supabase.roles r, better_supabase.permissions p
where rp.role_id = r.id and rp.permission_id = p.id
  and r.key = 'owner' and p.key >= 'n';

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

insert into auth.users (id, email)
values ('00000000-0000-4000-8000-0000000000d9', 'leaving@example.test');
insert into public.memberships (organization_id, user_id, role)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000d9', (select id from better_supabase.roles limit 1));

select lives_ok(
  $$delete from auth.users where id = '00000000-0000-4000-8000-0000000000d9'$$,
  'deleting a user with a membership bumps no version for the deleted user'
);

select * from finish();
rollback;
