-- http_tick posts to the URL in Vault with its bearer token, skips while a
-- secret is missing, raises without pg_net, and only the service role runs it.
-- A stand-in net.http_post records each call; the transaction rolls it back.
begin;
select plan(9);

select ok(
  (select p.prosecdef from pg_catalog.pg_proc p where p.oid = 'better_supabase.http_tick()'::regprocedure),
  'http_tick is security definer'
);

select ok(
  not pg_catalog.has_function_privilege('anon', 'better_supabase.http_tick()', 'execute')
    and not pg_catalog.has_function_privilege('authenticated', 'better_supabase.http_tick()', 'execute'),
  'anon and authenticated cannot run http_tick'
);

select ok(
  pg_catalog.has_function_privilege('service_role', 'better_supabase.http_tick()', 'execute'),
  'the service role runs http_tick'
);

select throws_ok(
  $$ select better_supabase.http_tick() $$,
  'P0001',
  'the queue tick needs pg_net: create extension pg_net',
  'without pg_net, http_tick raises'
);

create schema if not exists net;
create table net.tick_calls (url text, body jsonb, headers jsonb, timeout_milliseconds integer);
create function net.http_post(
  url text,
  body jsonb default '{}',
  params jsonb default '{}',
  headers jsonb default '{}',
  timeout_milliseconds integer default 5000
) returns bigint language sql as $$
  insert into net.tick_calls values (url, body, headers, timeout_milliseconds);
  select 42::bigint;
$$;
grant usage on schema net to service_role;
grant all on net.tick_calls to service_role;
grant execute on function net.http_post(text, jsonb, jsonb, jsonb, integer) to service_role;

set local role service_role;

select is(
  better_supabase.http_tick(),
  null,
  'without the Vault secrets, http_tick skips the tick'
);

reset role;
select vault.create_secret('https://app.example/api/jobs/drain', 'jobs_tick_url');
select vault.create_secret('tick-token', 'jobs_tick_token');
set local role service_role;

select is(
  better_supabase.http_tick(),
  42::bigint,
  'http_tick returns the pg_net request id'
);

select is(
  (select url from net.tick_calls),
  'https://app.example/api/jobs/drain',
  'it posts to the URL in jobs_tick_url'
);

select is(
  (select headers ->> 'authorization' from net.tick_calls),
  'Bearer tick-token',
  'it sends the token in jobs_tick_token as the bearer'
);

select is(
  (select count(*)::int from net.tick_calls),
  1,
  'one tick, one request'
);

select * from finish();
rollback;
