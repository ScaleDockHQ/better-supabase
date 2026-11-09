-- The sessions module's `options.hook` (ADR 0521): better_supabase.hook_plan
-- tells the access token hook how much to read. A refresh whose authz_ver is
-- still current and an OAuth client token read no memberships; every other
-- event reads them. User …00a1 is an admin of organization …0001 in
-- supabase/seed.sql.
begin;
select plan(13);

create temp table current_version as
select better_supabase.authz_version('00000000-0000-4000-8000-0000000000a1') as version;

create function pg_temp.refresh_event(version bigint, extra jsonb default '{}'::jsonb)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'user_id', '00000000-0000-4000-8000-0000000000a1',
    'authentication_method', 'token_refresh',
    'claims', jsonb_build_object(
      'sub', '00000000-0000-4000-8000-0000000000a1',
      'authz_ver', version,
      'memberships', '[]'::jsonb
    ) || extra
  )
$$;

select is(
  better_supabase.hook_plan('{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"x"}}'),
  'full',
  'a sign-in without a previous token reads everything'
);

select is(
  better_supabase.hook_plan(pg_temp.refresh_event((select version from current_version))),
  'reuse',
  'a refresh with the current authz_ver reuses the claims'
);

select is(
  better_supabase.hook_plan(pg_temp.refresh_event((select version from current_version) + 1)),
  'full',
  'a refresh with a stale authz_ver reads again'
);

select is(
  better_supabase.hook_plan(pg_temp.refresh_event(
    (select version from current_version), '{"permissions_truncated":true}')),
  'full',
  'a truncated permissions claim reads again'
);

select is(
  better_supabase.hook_plan(pg_temp.refresh_event(
    (select version from current_version), '{"team_ids_truncated":true}')),
  'full',
  'a partial team_ids claim reads again'
);

select is(
  better_supabase.hook_plan(
    jsonb_set(pg_temp.refresh_event((select version from current_version)),
      '{claims,memberships}', '"x"')),
  'full',
  'a memberships claim that is not an array reads again'
);

select is(
  better_supabase.hook_plan(
    jsonb_set(pg_temp.refresh_event((select version from current_version)),
      '{authentication_method}', '"password"')),
  'full',
  'only a token_refresh reuses claims'
);

select is(
  better_supabase.hook_plan(pg_temp.refresh_event(
    (select version from current_version), '{"client_id":"mcp-client"}')),
  'slim',
  'a token with a client_id is slim, whatever the version'
);

select is(
  better_supabase.hook_plan(
    '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"client_id":""}}'),
  'full',
  'an empty client_id is not an OAuth client token'
);

-- Membership reads per hook call, counted in this transaction.
set local track_functions = 'all';

select rbac.custom_access_token_hook(
  pg_temp.refresh_event((select version from current_version)));

select is(
  coalesce((select calls from pg_stat_get_xact_function_calls(
    'better_supabase.membership_claims(uuid)'::regprocedure) as t(calls)), 0),
  0::bigint,
  'a fast refresh makes 0 membership reads'
);

select is(
  rbac.custom_access_token_hook(
    pg_temp.refresh_event((select version from current_version))),
  pg_temp.refresh_event((select version from current_version)),
  'a fast refresh returns the event unchanged'
);

select rbac.custom_access_token_hook(
  '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1"}}');

select is(
  coalesce((select calls from pg_stat_get_xact_function_calls(
    'better_supabase.membership_claims(uuid)'::regprocedure) as t(calls)), 0),
  1::bigint,
  'a full read makes 1 membership read'
);

select is(
  (rbac.custom_access_token_hook(
    pg_temp.refresh_event((select version from current_version), '{"client_id":"mcp-client"}'))
    -> 'claims' -> 'memberships'),
  '[]'::jsonb,
  'a client token leaves the claims it was given'
);

select * from finish();
rollback;
