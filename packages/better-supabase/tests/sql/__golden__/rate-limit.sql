-- ==== alone: schema supabase/schemas/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block rate-limit@1 managed
-- @bsb-hash sha256:f5bd5b81ef18d3bb85a2d0ec80544952ac28da4ed430ecde7a7e687edf5127f9
-- Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists "better_supabase"."rate_limit_rules" (
  "scope" text primary key,
  "max_requests" integer not null check ("max_requests" > 0),
  "period" interval not null check ("period" > interval '0'),
  "key_claim" text not null default 'sub'
);

create unlogged table if not exists "better_supabase"."rate_limits" (
  "scope" text not null,
  "key" text not null,
  "window_start" timestamptz not null,
  "hits" integer not null,
  primary key ("scope", "key")
);
-- The window length the counter was last hit with, so purge_rate_limits keeps
-- a counter for its whole window when no rule names its period.
alter table "better_supabase"."rate_limits" add column if not exists "period" interval;

alter table "better_supabase"."rate_limit_rules" enable row level security;
alter table "better_supabase"."rate_limits" enable row level security;
revoke all on table "better_supabase"."rate_limit_rules" from public, anon, authenticated;
revoke all on table "better_supabase"."rate_limits" from public, anon, authenticated;

-- select better_supabase.set_rate_limit('/rpc/send_invite', 5, interval '1 minute');
-- A null max_requests removes the rule.
create or replace function better_supabase.set_rate_limit(
  scope text,
  max_requests integer,
  period interval default interval '1 minute',
  key_claim text default 'sub'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if max_requests is null then
    delete from "better_supabase"."rate_limit_rules" r where r."scope" = set_rate_limit.scope;
    delete from "better_supabase"."rate_limits" l where l."scope" = set_rate_limit.scope;
    return;
  end if;
  insert into "better_supabase"."rate_limit_rules" as r ("scope", "max_requests", "period", "key_claim")
  values (scope, max_requests, period, key_claim)
  on conflict ("scope") do update
    set "max_requests" = excluded."max_requests", "period" = excluded."period", "key_claim" = excluded."key_claim";
end
$$;

revoke execute on function better_supabase.set_rate_limit(text, integer, interval, text) from public, anon, authenticated;
grant execute on function better_supabase.set_rate_limit(text, integer, interval, text) to service_role;

-- PostgREST's pre-request hook. GET and HEAD run read-only (and may be served
-- by a replica), so only writes count. A POST to /rpc for a stable or
-- immutable function also runs read-only and isn't counted either. The
-- service role is never limited.
-- With your own db_pre_request, call it from there: perform better_supabase.check_request();
create or replace function better_supabase.check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule "better_supabase"."rate_limit_rules";
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from "better_supabase"."rate_limit_rules" r where r."scope" in ('*', path) order by r."scope"
  loop
    caller := coalesce(
      claims ->> rule."key_claim",
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
    values (rule."scope", caller, now(), 1, rule."period")
    on conflict on constraint rate_limits_pkey do update set
      "window_start" = case when l."window_start" + rule."period" <= now() then now() else l."window_start" end,
      "hits" = case when l."window_start" + rule."period" <= now() then 1 else l."hits" + 1 end,
      "period" = rule."period"
    returning l."hits", l."window_start" into used, started;
    if used > rule."max_requests" then
      retry := greatest(1, ceil(extract(epoch from started + rule."period" - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule."scope", rule."max_requests", rule."period"),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$$;

revoke execute on function better_supabase.check_request() from public;
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;

-- Counts one hit of key (an API key, a public token, a tenant, a chat
-- thread) against scope, for route handlers that limit something other than
-- Data API writes: allowed, the hits left in the window and, when refused,
-- the seconds until it ends. The limit is scope's rule in rate_limit_rules,
-- or max_requests per period when given.
create or replace function better_supabase.hit_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns table (allowed boolean, remaining integer, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  rule "better_supabase"."rate_limit_rules";
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule."max_requests");
  limit_period := coalesce(period, rule."period");
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  values (scope, key, now(), 1, limit_period)
  on conflict on constraint rate_limits_pkey do update set
    "window_start" = case when l."window_start" + limit_period <= now() then now() else l."window_start" end,
    "hits" = case when l."window_start" + limit_period <= now() then 1 else l."hits" + 1 end,
    "period" = limit_period
  returning l."hits", l."window_start" into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$$;
revoke execute on function better_supabase.hit_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.hit_rate_limit(text, text, integer, interval) to service_role;

create or replace function better_supabase.check_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select to_jsonb(h) from better_supabase.hit_rate_limit(scope, key, max_requests, period) h
$$;
revoke execute on function better_supabase.check_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limit(text, text, integer, interval) to service_role;

-- Counts one hit against several limits at once: hits is a JSON array of
-- { scope, key, max_requests?, period? }, each with its own scope and key.
-- The counters are locked in a fixed order and the hit counts only when every
-- limit allows it, so a refused call leaves every counter as it was. Returns
-- { allowed, blocked, retry_after, results }: blocked is the index of the first
-- limit over its maximum, retry_after the longest wait of the refusing
-- limits, and results one { allowed, remaining, retry_after } per hit.
create or replace function better_supabase.check_rate_limits(hits jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule "better_supabase"."rate_limit_rules";
  counter "better_supabase"."rate_limits";
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule."max_requests");
    limit_period := coalesce((hit ->> 'period')::interval, rule."period");
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict on constraint rate_limits_pkey do nothing;

  perform 1
  from "better_supabase"."rate_limits" l
  join unnest(scopes, keys) as u(scope, key) on l."scope" = u.scope and l."key" = u.key
  order by l."scope", l."key"
  for update of l;

  for i in 1 .. total loop
    select * into counter from "better_supabase"."rate_limits" l
    where l."scope" = scopes[i] and l."key" = keys[i];
    if counter."window_start" + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter."hits";
      starts := starts || counter."window_start";
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update "better_supabase"."rate_limits" l set
        "window_start" = starts[i],
        "hits" = used[i] + 1,
        "period" = periods[i]
      where l."scope" = scopes[i] and l."key" = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$$;
revoke execute on function better_supabase.check_rate_limits(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limits(jsonb) to service_role;

-- Deletes up to batch counters whose window has ended: the period the
-- counter was last hit with, else its rule's, else a day (counters from
-- before the period column). Every caller keeps a row until then, so
-- schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    select l."scope", l."key" from "better_supabase"."rate_limits" l
    left join "better_supabase"."rate_limit_rules" r on r."scope" = l."scope"
    where l."window_start" + coalesce(l."period", r."period", interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from "better_supabase"."rate_limits" l
    using expired e
    where l."scope" = e.scope and l."key" = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block-data rate-limit
-- @bsb-hash sha256:15898458bc504e8d36285d83cc2c6a240321839e73d4a58c113b49c3b93d8212
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block rate-limit@1 managed
-- @bsb-hash sha256:f5bd5b81ef18d3bb85a2d0ec80544952ac28da4ed430ecde7a7e687edf5127f9
-- Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists "better_supabase"."rate_limit_rules" (
  "scope" text primary key,
  "max_requests" integer not null check ("max_requests" > 0),
  "period" interval not null check ("period" > interval '0'),
  "key_claim" text not null default 'sub'
);

create unlogged table if not exists "better_supabase"."rate_limits" (
  "scope" text not null,
  "key" text not null,
  "window_start" timestamptz not null,
  "hits" integer not null,
  primary key ("scope", "key")
);
-- The window length the counter was last hit with, so purge_rate_limits keeps
-- a counter for its whole window when no rule names its period.
alter table "better_supabase"."rate_limits" add column if not exists "period" interval;

alter table "better_supabase"."rate_limit_rules" enable row level security;
alter table "better_supabase"."rate_limits" enable row level security;
revoke all on table "better_supabase"."rate_limit_rules" from public, anon, authenticated;
revoke all on table "better_supabase"."rate_limits" from public, anon, authenticated;

-- select better_supabase.set_rate_limit('/rpc/send_invite', 5, interval '1 minute');
-- A null max_requests removes the rule.
create or replace function better_supabase.set_rate_limit(
  scope text,
  max_requests integer,
  period interval default interval '1 minute',
  key_claim text default 'sub'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if max_requests is null then
    delete from "better_supabase"."rate_limit_rules" r where r."scope" = set_rate_limit.scope;
    delete from "better_supabase"."rate_limits" l where l."scope" = set_rate_limit.scope;
    return;
  end if;
  insert into "better_supabase"."rate_limit_rules" as r ("scope", "max_requests", "period", "key_claim")
  values (scope, max_requests, period, key_claim)
  on conflict ("scope") do update
    set "max_requests" = excluded."max_requests", "period" = excluded."period", "key_claim" = excluded."key_claim";
end
$$;

revoke execute on function better_supabase.set_rate_limit(text, integer, interval, text) from public, anon, authenticated;
grant execute on function better_supabase.set_rate_limit(text, integer, interval, text) to service_role;

-- PostgREST's pre-request hook. GET and HEAD run read-only (and may be served
-- by a replica), so only writes count. A POST to /rpc for a stable or
-- immutable function also runs read-only and isn't counted either. The
-- service role is never limited.
-- With your own db_pre_request, call it from there: perform better_supabase.check_request();
create or replace function better_supabase.check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule "better_supabase"."rate_limit_rules";
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from "better_supabase"."rate_limit_rules" r where r."scope" in ('*', path) order by r."scope"
  loop
    caller := coalesce(
      claims ->> rule."key_claim",
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
    values (rule."scope", caller, now(), 1, rule."period")
    on conflict on constraint rate_limits_pkey do update set
      "window_start" = case when l."window_start" + rule."period" <= now() then now() else l."window_start" end,
      "hits" = case when l."window_start" + rule."period" <= now() then 1 else l."hits" + 1 end,
      "period" = rule."period"
    returning l."hits", l."window_start" into used, started;
    if used > rule."max_requests" then
      retry := greatest(1, ceil(extract(epoch from started + rule."period" - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule."scope", rule."max_requests", rule."period"),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$$;

revoke execute on function better_supabase.check_request() from public;
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;

-- Counts one hit of key (an API key, a public token, a tenant, a chat
-- thread) against scope, for route handlers that limit something other than
-- Data API writes: allowed, the hits left in the window and, when refused,
-- the seconds until it ends. The limit is scope's rule in rate_limit_rules,
-- or max_requests per period when given.
create or replace function better_supabase.hit_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns table (allowed boolean, remaining integer, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  rule "better_supabase"."rate_limit_rules";
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule."max_requests");
  limit_period := coalesce(period, rule."period");
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  values (scope, key, now(), 1, limit_period)
  on conflict on constraint rate_limits_pkey do update set
    "window_start" = case when l."window_start" + limit_period <= now() then now() else l."window_start" end,
    "hits" = case when l."window_start" + limit_period <= now() then 1 else l."hits" + 1 end,
    "period" = limit_period
  returning l."hits", l."window_start" into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$$;
revoke execute on function better_supabase.hit_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.hit_rate_limit(text, text, integer, interval) to service_role;

create or replace function better_supabase.check_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select to_jsonb(h) from better_supabase.hit_rate_limit(scope, key, max_requests, period) h
$$;
revoke execute on function better_supabase.check_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limit(text, text, integer, interval) to service_role;

-- Counts one hit against several limits at once: hits is a JSON array of
-- { scope, key, max_requests?, period? }, each with its own scope and key.
-- The counters are locked in a fixed order and the hit counts only when every
-- limit allows it, so a refused call leaves every counter as it was. Returns
-- { allowed, blocked, retry_after, results }: blocked is the index of the first
-- limit over its maximum, retry_after the longest wait of the refusing
-- limits, and results one { allowed, remaining, retry_after } per hit.
create or replace function better_supabase.check_rate_limits(hits jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule "better_supabase"."rate_limit_rules";
  counter "better_supabase"."rate_limits";
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule."max_requests");
    limit_period := coalesce((hit ->> 'period')::interval, rule."period");
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict on constraint rate_limits_pkey do nothing;

  perform 1
  from "better_supabase"."rate_limits" l
  join unnest(scopes, keys) as u(scope, key) on l."scope" = u.scope and l."key" = u.key
  order by l."scope", l."key"
  for update of l;

  for i in 1 .. total loop
    select * into counter from "better_supabase"."rate_limits" l
    where l."scope" = scopes[i] and l."key" = keys[i];
    if counter."window_start" + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter."hits";
      starts := starts || counter."window_start";
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update "better_supabase"."rate_limits" l set
        "window_start" = starts[i],
        "hits" = used[i] + 1,
        "period" = periods[i]
      where l."scope" = scopes[i] and l."key" = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$$;
revoke execute on function better_supabase.check_rate_limits(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limits(jsonb) to service_role;

-- Deletes up to batch counters whose window has ended: the period the
-- counter was last hit with, else its rule's, else a day (counters from
-- before the period column). Every caller keeps a row until then, so
-- schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    select l."scope", l."key" from "better_supabase"."rate_limits" l
    left join "better_supabase"."rate_limit_rules" r on r."scope" = l."scope"
    where l."window_start" + coalesce(l."period", r."period", interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from "better_supabase"."rate_limits" l
    using expired e
    where l."scope" = e.scope and l."key" = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block-data rate-limit
-- @bsb-hash sha256:15898458bc504e8d36285d83cc2c6a240321839e73d4a58c113b49c3b93d8212
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block rate-limit@1 managed
-- @bsb-hash sha256:d8395dd9413fd01086e7582ad85494c9e1383663a3c637a5e63067bbb6bbbb99
-- Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists "app_private"."rate_limit_rules" (
  "scope" text primary key,
  "max_requests" integer not null check ("max_requests" > 0),
  "period" interval not null check ("period" > interval '0'),
  "key_claim" text not null default 'sub'
);

create unlogged table if not exists "app_private"."rate_limits" (
  "scope" text not null,
  "key" text not null,
  "window_start" timestamptz not null,
  "hits" integer not null,
  primary key ("scope", "key")
);
-- The window length the counter was last hit with, so purge_rate_limits keeps
-- a counter for its whole window when no rule names its period.
alter table "app_private"."rate_limits" add column if not exists "period" interval;

alter table "app_private"."rate_limit_rules" enable row level security;
alter table "app_private"."rate_limits" enable row level security;
revoke all on table "app_private"."rate_limit_rules" from public, anon, authenticated;
revoke all on table "app_private"."rate_limits" from public, anon, authenticated;

-- select better_supabase.set_rate_limit('/rpc/send_invite', 5, interval '1 minute');
-- A null max_requests removes the rule.
create or replace function better_supabase.set_rate_limit(
  scope text,
  max_requests integer,
  period interval default interval '1 minute',
  key_claim text default 'sub'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if max_requests is null then
    delete from "app_private"."rate_limit_rules" r where r."scope" = set_rate_limit.scope;
    delete from "app_private"."rate_limits" l where l."scope" = set_rate_limit.scope;
    return;
  end if;
  insert into "app_private"."rate_limit_rules" as r ("scope", "max_requests", "period", "key_claim")
  values (scope, max_requests, period, key_claim)
  on conflict ("scope") do update
    set "max_requests" = excluded."max_requests", "period" = excluded."period", "key_claim" = excluded."key_claim";
end
$$;

revoke execute on function better_supabase.set_rate_limit(text, integer, interval, text) from public, anon, authenticated;
grant execute on function better_supabase.set_rate_limit(text, integer, interval, text) to service_role;

-- PostgREST's pre-request hook. GET and HEAD run read-only (and may be served
-- by a replica), so only writes count. A POST to /rpc for a stable or
-- immutable function also runs read-only and isn't counted either. The
-- service role is never limited.
-- With your own db_pre_request, call it from there: perform better_supabase.check_request();
create or replace function better_supabase.check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule "app_private"."rate_limit_rules";
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from "app_private"."rate_limit_rules" r where r."scope" in ('*', path) order by r."scope"
  loop
    caller := coalesce(
      claims ->> rule."key_claim",
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into "app_private"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
    values (rule."scope", caller, now(), 1, rule."period")
    on conflict on constraint rate_limits_pkey do update set
      "window_start" = case when l."window_start" + rule."period" <= now() then now() else l."window_start" end,
      "hits" = case when l."window_start" + rule."period" <= now() then 1 else l."hits" + 1 end,
      "period" = rule."period"
    returning l."hits", l."window_start" into used, started;
    if used > rule."max_requests" then
      retry := greatest(1, ceil(extract(epoch from started + rule."period" - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule."scope", rule."max_requests", rule."period"),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$$;

revoke execute on function better_supabase.check_request() from public;
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;

-- Counts one hit of key (an API key, a public token, a tenant, a chat
-- thread) against scope, for route handlers that limit something other than
-- Data API writes: allowed, the hits left in the window and, when refused,
-- the seconds until it ends. The limit is scope's rule in rate_limit_rules,
-- or max_requests per period when given.
create or replace function better_supabase.hit_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns table (allowed boolean, remaining integer, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  rule "app_private"."rate_limit_rules";
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from "app_private"."rate_limit_rules" r where r."scope" = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule."max_requests");
  limit_period := coalesce(period, rule."period");
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into "app_private"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  values (scope, key, now(), 1, limit_period)
  on conflict on constraint rate_limits_pkey do update set
    "window_start" = case when l."window_start" + limit_period <= now() then now() else l."window_start" end,
    "hits" = case when l."window_start" + limit_period <= now() then 1 else l."hits" + 1 end,
    "period" = limit_period
  returning l."hits", l."window_start" into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$$;
revoke execute on function better_supabase.hit_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.hit_rate_limit(text, text, integer, interval) to service_role;

create or replace function better_supabase.check_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select to_jsonb(h) from better_supabase.hit_rate_limit(scope, key, max_requests, period) h
$$;
revoke execute on function better_supabase.check_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limit(text, text, integer, interval) to service_role;

-- Counts one hit against several limits at once: hits is a JSON array of
-- { scope, key, max_requests?, period? }, each with its own scope and key.
-- The counters are locked in a fixed order and the hit counts only when every
-- limit allows it, so a refused call leaves every counter as it was. Returns
-- { allowed, blocked, retry_after, results }: blocked is the index of the first
-- limit over its maximum, retry_after the longest wait of the refusing
-- limits, and results one { allowed, remaining, retry_after } per hit.
create or replace function better_supabase.check_rate_limits(hits jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule "app_private"."rate_limit_rules";
  counter "app_private"."rate_limits";
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from "app_private"."rate_limit_rules" r where r."scope" = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule."max_requests");
    limit_period := coalesce((hit ->> 'period')::interval, rule."period");
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into "app_private"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict on constraint rate_limits_pkey do nothing;

  perform 1
  from "app_private"."rate_limits" l
  join unnest(scopes, keys) as u(scope, key) on l."scope" = u.scope and l."key" = u.key
  order by l."scope", l."key"
  for update of l;

  for i in 1 .. total loop
    select * into counter from "app_private"."rate_limits" l
    where l."scope" = scopes[i] and l."key" = keys[i];
    if counter."window_start" + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter."hits";
      starts := starts || counter."window_start";
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update "app_private"."rate_limits" l set
        "window_start" = starts[i],
        "hits" = used[i] + 1,
        "period" = periods[i]
      where l."scope" = scopes[i] and l."key" = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$$;
revoke execute on function better_supabase.check_rate_limits(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limits(jsonb) to service_role;

-- Deletes up to batch counters whose window has ended: the period the
-- counter was last hit with, else its rule's, else a day (counters from
-- before the period column). Every caller keeps a row until then, so
-- schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    select l."scope", l."key" from "app_private"."rate_limits" l
    left join "app_private"."rate_limit_rules" r on r."scope" = l."scope"
    where l."window_start" + coalesce(l."period", r."period", interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from "app_private"."rate_limits" l
    using expired e
    where l."scope" = e.scope and l."key" = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block-data rate-limit
-- @bsb-hash sha256:15898458bc504e8d36285d83cc2c6a240321839e73d4a58c113b49c3b93d8212
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block rate-limit@1 managed
-- @bsb-hash sha256:4d3bb1a5ad54daa21449eb400f2e65f890da27dd495ea708af1b554e994c99d0
-- Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists "better_supabase"."rate_limit_rules" (
  "scope" text primary key,
  "max_requests" integer not null check ("max_requests" > 0),
  "period" interval not null check ("period" > interval '0'),
  "key_claim" text not null default 'sub'
);

create unlogged table if not exists "better_supabase"."rate_limits" (
  "scope" text not null,
  "key" text not null,
  "window_start" timestamptz not null,
  "hits" integer not null,
  primary key ("scope", "key")
);
-- The window length the counter was last hit with, so purge_rate_limits keeps
-- a counter for its whole window when no rule names its period.
alter table "better_supabase"."rate_limits" add column if not exists "period" interval;

alter table "better_supabase"."rate_limit_rules" enable row level security;
alter table "better_supabase"."rate_limits" enable row level security;
revoke all on table "better_supabase"."rate_limit_rules" from public, anon, authenticated;
revoke all on table "better_supabase"."rate_limits" from public, anon, authenticated;

-- select better_supabase.set_rate_limit('/rpc/send_invite', 5, interval '1 minute');
-- A null max_requests removes the rule.
create or replace function better_supabase.set_rate_limit(
  scope text,
  max_requests integer,
  period interval default interval '1 minute',
  key_claim text default 'sub'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if max_requests is null then
    delete from "better_supabase"."rate_limit_rules" r where r."scope" = set_rate_limit.scope;
    delete from "better_supabase"."rate_limits" l where l."scope" = set_rate_limit.scope;
    return;
  end if;
  insert into "better_supabase"."rate_limit_rules" as r ("scope", "max_requests", "period", "key_claim")
  values (scope, max_requests, period, key_claim)
  on conflict ("scope") do update
    set "max_requests" = excluded."max_requests", "period" = excluded."period", "key_claim" = excluded."key_claim";
end
$$;

revoke execute on function better_supabase.set_rate_limit(text, integer, interval, text) from public, anon, authenticated;
grant execute on function better_supabase.set_rate_limit(text, integer, interval, text) to service_role;

-- PostgREST's pre-request hook. GET and HEAD run read-only (and may be served
-- by a replica), so only writes count. A POST to /rpc for a stable or
-- immutable function also runs read-only and isn't counted either. The
-- service role is never limited.
-- With your own db_pre_request, call it from there: perform better_supabase.check_request();
create or replace function better_supabase.check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule "better_supabase"."rate_limit_rules";
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from "better_supabase"."rate_limit_rules" r where r."scope" in ('*', path) order by r."scope"
  loop
    caller := coalesce(
      claims ->> rule."key_claim",
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
    values (rule."scope", caller, now(), 1, rule."period")
    on conflict on constraint rate_limits_pkey do update set
      "window_start" = case when l."window_start" + rule."period" <= now() then now() else l."window_start" end,
      "hits" = case when l."window_start" + rule."period" <= now() then 1 else l."hits" + 1 end,
      "period" = rule."period"
    returning l."hits", l."window_start" into used, started;
    if used > rule."max_requests" then
      retry := greatest(1, ceil(extract(epoch from started + rule."period" - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule."scope", rule."max_requests", rule."period"),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$$;

revoke execute on function better_supabase.check_request() from public;
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;

-- Counts one hit of key (an API key, a public token, a tenant, a chat
-- thread) against scope, for route handlers that limit something other than
-- Data API writes: allowed, the hits left in the window and, when refused,
-- the seconds until it ends. The limit is scope's rule in rate_limit_rules,
-- or max_requests per period when given.
create or replace function better_supabase.hit_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns table (allowed boolean, remaining integer, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  rule "better_supabase"."rate_limit_rules";
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule."max_requests");
  limit_period := coalesce(period, rule."period");
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  values (scope, key, now(), 1, limit_period)
  on conflict on constraint rate_limits_pkey do update set
    "window_start" = case when l."window_start" + limit_period <= now() then now() else l."window_start" end,
    "hits" = case when l."window_start" + limit_period <= now() then 1 else l."hits" + 1 end,
    "period" = limit_period
  returning l."hits", l."window_start" into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$$;
revoke execute on function better_supabase.hit_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.hit_rate_limit(text, text, integer, interval) to service_role;

create or replace function better_supabase.check_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select to_jsonb(h) from better_supabase.hit_rate_limit(scope, key, max_requests, period) h
$$;
revoke execute on function better_supabase.check_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limit(text, text, integer, interval) to service_role;

-- Counts one hit against several limits at once: hits is a JSON array of
-- { scope, key, max_requests?, period? }, each with its own scope and key.
-- The counters are locked in a fixed order and the hit counts only when every
-- limit allows it, so a refused call leaves every counter as it was. Returns
-- { allowed, blocked, retry_after, results }: blocked is the index of the first
-- limit over its maximum, retry_after the longest wait of the refusing
-- limits, and results one { allowed, remaining, retry_after } per hit.
create or replace function better_supabase.check_rate_limits(hits jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule "better_supabase"."rate_limit_rules";
  counter "better_supabase"."rate_limits";
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule."max_requests");
    limit_period := coalesce((hit ->> 'period')::interval, rule."period");
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict on constraint rate_limits_pkey do nothing;

  perform 1
  from "better_supabase"."rate_limits" l
  join unnest(scopes, keys) as u(scope, key) on l."scope" = u.scope and l."key" = u.key
  order by l."scope", l."key"
  for update of l;

  for i in 1 .. total loop
    select * into counter from "better_supabase"."rate_limits" l
    where l."scope" = scopes[i] and l."key" = keys[i];
    if counter."window_start" + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter."hits";
      starts := starts || counter."window_start";
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update "better_supabase"."rate_limits" l set
        "window_start" = starts[i],
        "hits" = used[i] + 1,
        "period" = periods[i]
      where l."scope" = scopes[i] and l."key" = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$$;
revoke execute on function better_supabase.check_rate_limits(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limits(jsonb) to service_role;

-- Deletes up to batch counters whose window has ended: the period the
-- counter was last hit with, else its rule's, else a day (counters from
-- before the period column). Every caller keeps a row until then, so
-- schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    select l."scope", l."key" from "better_supabase"."rate_limits" l
    left join "better_supabase"."rate_limit_rules" r on r."scope" = l."scope"
    where l."window_start" + coalesce(l."period", r."period", interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from "better_supabase"."rate_limits" l
    using expired e
    where l."scope" = e.scope and l."key" = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;

-- blocks.rate-limit.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."set_rate_limit"(scope text, max_requests integer, period interval default interval '1 minute', key_claim text default 'sub')
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_rate_limit"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_rate_limit"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "api"."set_rate_limit"(text, integer, interval, text) to service_role;

create or replace function "api"."check_request"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_request"() $$;
revoke execute on function "api"."check_request"() from public;
grant execute on function "api"."check_request"() to anon, authenticated, service_role;

create or replace function "api"."hit_rate_limit"(scope text, key text, max_requests integer default null, period interval default null)
returns table (allowed boolean, remaining integer, retry_after integer)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."hit_rate_limit"($1, $2, $3, $4) $$;
revoke execute on function "api"."hit_rate_limit"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "api"."hit_rate_limit"(text, text, integer, interval) to service_role;

create or replace function "api"."check_rate_limit"(scope text, key text, max_requests integer default null, period interval default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_rate_limit"($1, $2, $3, $4) $$;
revoke execute on function "api"."check_rate_limit"(text, text, integer, interval) from public, anon, authenticated;
grant execute on function "api"."check_rate_limit"(text, text, integer, interval) to service_role;

create or replace function "api"."check_rate_limits"(hits jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_rate_limits"($1) $$;
revoke execute on function "api"."check_rate_limits"(jsonb) from public, anon, authenticated;
grant execute on function "api"."check_rate_limits"(jsonb) to service_role;

create or replace function "api"."purge_rate_limits"(batch integer default 10000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_rate_limits"($1) $$;
revoke execute on function "api"."purge_rate_limits"(integer) from public, anon, authenticated;
grant execute on function "api"."purge_rate_limits"(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block-data rate-limit
-- @bsb-hash sha256:15898458bc504e8d36285d83cc2c6a240321839e73d4a58c113b49c3b93d8212
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block rate-limit@1 managed
-- @bsb-hash sha256:28fc356a2bdbf5fff8583f0c4d9736a34c0e22b198c386be1389b011b2d91673
-- Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
-- better_supabase.rate_limit_rules is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."rate_limit_rules" add column if not exists "scope" text;
alter table "better_supabase"."rate_limit_rules" add column if not exists "max_requests" integer check ("max_requests" > 0);
alter table "better_supabase"."rate_limit_rules" add column if not exists "period" interval check ("period" > interval '0');
alter table "better_supabase"."rate_limit_rules" add column if not exists "key_claim" text not null default 'sub';
create unique index if not exists "bsb_rate_limit_rules_scope_key" on "better_supabase"."rate_limit_rules" ("scope");

-- better_supabase.rate_limits is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."rate_limits" add column if not exists "scope" text;
alter table "better_supabase"."rate_limits" add column if not exists "key" text;
alter table "better_supabase"."rate_limits" add column if not exists "window_start" timestamptz;
alter table "better_supabase"."rate_limits" add column if not exists "hits" integer;
create unique index if not exists "bsb_rate_limits_scope_key_key" on "better_supabase"."rate_limits" ("scope", "key");
-- The window length the counter was last hit with, so purge_rate_limits keeps
-- a counter for its whole window when no rule names its period.
alter table "better_supabase"."rate_limits" add column if not exists "period" interval;

alter table "better_supabase"."rate_limit_rules" enable row level security;
alter table "better_supabase"."rate_limits" enable row level security;

-- select better_supabase.set_rate_limit('/rpc/send_invite', 5, interval '1 minute');
-- A null max_requests removes the rule.
create or replace function better_supabase.set_rate_limit(
  scope text,
  max_requests integer,
  period interval default interval '1 minute',
  key_claim text default 'sub'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if max_requests is null then
    delete from "better_supabase"."rate_limit_rules" r where r."scope" = set_rate_limit.scope;
    delete from "better_supabase"."rate_limits" l where l."scope" = set_rate_limit.scope;
    return;
  end if;
  insert into "better_supabase"."rate_limit_rules" as r ("scope", "max_requests", "period", "key_claim")
  values (scope, max_requests, period, key_claim)
  on conflict ("scope") do update
    set "max_requests" = excluded."max_requests", "period" = excluded."period", "key_claim" = excluded."key_claim";
end
$$;

revoke execute on function better_supabase.set_rate_limit(text, integer, interval, text) from public, anon, authenticated;
grant execute on function better_supabase.set_rate_limit(text, integer, interval, text) to service_role;

-- PostgREST's pre-request hook. GET and HEAD run read-only (and may be served
-- by a replica), so only writes count. A POST to /rpc for a stable or
-- immutable function also runs read-only and isn't counted either. The
-- service role is never limited.
-- With your own db_pre_request, call it from there: perform better_supabase.check_request();
create or replace function better_supabase.check_request()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  method text := current_setting('request.method', true);
  path text := current_setting('request.path', true);
  claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  rule "better_supabase"."rate_limit_rules";
  caller text;
  used integer;
  started timestamptz;
  retry integer;
begin
  if method is null or method not in ('POST', 'PATCH', 'PUT', 'DELETE') then
    return;
  end if;
  if current_setting('transaction_read_only', true) = 'on' then
    return;
  end if;
  if claims ->> 'role' = 'service_role' then
    return;
  end if;
  for rule in
    select * from "better_supabase"."rate_limit_rules" r where r."scope" in ('*', path) order by r."scope"
  loop
    caller := coalesce(
      claims ->> rule."key_claim",
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
    values (rule."scope", caller, now(), 1, rule."period")
    on conflict ("scope", "key") do update set
      "window_start" = case when l."window_start" + rule."period" <= now() then now() else l."window_start" end,
      "hits" = case when l."window_start" + rule."period" <= now() then 1 else l."hits" + 1 end,
      "period" = rule."period"
    returning l."hits", l."window_start" into used, started;
    if used > rule."max_requests" then
      retry := greatest(1, ceil(extract(epoch from started + rule."period" - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule."scope", rule."max_requests", rule."period"),
          'details', format('Retry after %s seconds.', retry),
          'hint', null
        )::text,
        detail = json_build_object(
          'status', 429,
          'status_text', 'Too Many Requests',
          'headers', json_build_object('Retry-After', retry::text)
        )::text;
    end if;
  end loop;
end
$$;

revoke execute on function better_supabase.check_request() from public;
grant execute on function better_supabase.check_request() to anon, authenticated, service_role;

-- Counts one hit of key (an API key, a public token, a tenant, a chat
-- thread) against scope, for route handlers that limit something other than
-- Data API writes: allowed, the hits left in the window and, when refused,
-- the seconds until it ends. The limit is scope's rule in rate_limit_rules,
-- or max_requests per period when given.
create or replace function better_supabase.hit_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns table (allowed boolean, remaining integer, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  rule "better_supabase"."rate_limit_rules";
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule."max_requests");
  limit_period := coalesce(period, rule."period");
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  values (scope, key, now(), 1, limit_period)
  on conflict ("scope", "key") do update set
    "window_start" = case when l."window_start" + limit_period <= now() then now() else l."window_start" end,
    "hits" = case when l."window_start" + limit_period <= now() then 1 else l."hits" + 1 end,
    "period" = limit_period
  returning l."hits", l."window_start" into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$$;
revoke execute on function better_supabase.hit_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.hit_rate_limit(text, text, integer, interval) to service_role;

create or replace function better_supabase.check_rate_limit(
  scope text,
  key text,
  max_requests integer default null,
  period interval default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select to_jsonb(h) from better_supabase.hit_rate_limit(scope, key, max_requests, period) h
$$;
revoke execute on function better_supabase.check_rate_limit(text, text, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limit(text, text, integer, interval) to service_role;

-- Counts one hit against several limits at once: hits is a JSON array of
-- { scope, key, max_requests?, period? }, each with its own scope and key.
-- The counters are locked in a fixed order and the hit counts only when every
-- limit allows it, so a refused call leaves every counter as it was. Returns
-- { allowed, blocked, retry_after, results }: blocked is the index of the first
-- limit over its maximum, retry_after the longest wait of the refusing
-- limits, and results one { allowed, remaining, retry_after } per hit.
create or replace function better_supabase.check_rate_limits(hits jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule "better_supabase"."rate_limit_rules";
  counter "better_supabase"."rate_limits";
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from "better_supabase"."rate_limit_rules" r where r."scope" = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule."max_requests");
    limit_period := coalesce((hit ->> 'period')::interval, rule."period");
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into "better_supabase"."rate_limits" as l ("scope", "key", "window_start", "hits", "period")
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict ("scope", "key") do nothing;

  perform 1
  from "better_supabase"."rate_limits" l
  join unnest(scopes, keys) as u(scope, key) on l."scope" = u.scope and l."key" = u.key
  order by l."scope", l."key"
  for update of l;

  for i in 1 .. total loop
    select * into counter from "better_supabase"."rate_limits" l
    where l."scope" = scopes[i] and l."key" = keys[i];
    if counter."window_start" + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter."hits";
      starts := starts || counter."window_start";
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update "better_supabase"."rate_limits" l set
        "window_start" = starts[i],
        "hits" = used[i] + 1,
        "period" = periods[i]
      where l."scope" = scopes[i] and l."key" = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$$;
revoke execute on function better_supabase.check_rate_limits(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.check_rate_limits(jsonb) to service_role;

-- Deletes up to batch counters whose window has ended: the period the
-- counter was last hit with, else its rule's, else a day (counters from
-- before the period column). Every caller keeps a row until then, so
-- schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    select l."scope", l."key" from "better_supabase"."rate_limits" l
    left join "better_supabase"."rate_limit_rules" r on r."scope" = l."scope"
    where l."window_start" + coalesce(l."period", r."period", interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from "better_supabase"."rate_limits" l
    using expired e
    where l."scope" = e.scope and l."key" = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_017_rate_limit.sql
-- better-supabase module: rate-limit
-- @bsb-block-data rate-limit
-- @bsb-hash sha256:15898458bc504e8d36285d83cc2c6a240321839e73d4a58c113b49c3b93d8212
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Points PostgREST's pre-request hook at check_request. It keeps an
-- existing pre-request function; chain from it.
do $$
declare
  current_hook text;
begin
  select split_part(setting, '=', 2) into current_hook
  from pg_catalog.pg_db_role_setting s
  join pg_catalog.pg_roles r on r.oid = s.setrole
  cross join lateral unnest(s.setconfig) setting
  where r.rolname = 'authenticator' and s.setdatabase = 0 and setting like 'pgrst.db_pre_request=%';
  if current_hook is null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  elsif current_hook <> 'better_supabase.check_request' then
    raise notice 'pgrst.db_pre_request is %; call better_supabase.check_request() from it', current_hook;
  end if;
end
$$;
notify pgrst, 'reload config';

insert into better_supabase.blocks (name, version, mode)
values ('rate-limit', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
