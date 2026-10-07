-- better-supabase module: rate-limit (0.5.1)
-- @bs-module rate-limit@1 managed
-- Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists better_supabase.rate_limit_rules (
  scope text primary key,
  max_requests integer not null check (max_requests > 0),
  period interval not null check (period > interval '0'),
  key_claim text not null default 'sub'
);

create unlogged table if not exists better_supabase.rate_limits (
  scope text not null,
  key text not null,
  window_start timestamptz not null,
  hits integer not null,
  primary key (scope, key)
);

alter table better_supabase.rate_limit_rules enable row level security;
alter table better_supabase.rate_limits enable row level security;
revoke all on table better_supabase.rate_limit_rules from anon, authenticated;
revoke all on table better_supabase.rate_limits from anon, authenticated;

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
begin
  if max_requests is null then
    delete from better_supabase.rate_limit_rules r where r.scope = set_rate_limit.scope;
    delete from better_supabase.rate_limits l where l.scope = set_rate_limit.scope;
    return;
  end if;
  insert into better_supabase.rate_limit_rules as r (scope, max_requests, period, key_claim)
  values (scope, max_requests, period, key_claim)
  on conflict on constraint rate_limit_rules_pkey do update
    set max_requests = excluded.max_requests, period = excluded.period, key_claim = excluded.key_claim;
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
  rule better_supabase.rate_limit_rules;
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
    select * from better_supabase.rate_limit_rules r where r.scope in ('*', path) order by r.scope
  loop
    caller := coalesce(
      claims ->> rule.key_claim,
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
    values (rule.scope, caller, now(), 1)
    on conflict on constraint rate_limits_pkey do update set
      window_start = case when l.window_start + rule.period <= now() then now() else l.window_start end,
      hits = case when l.window_start + rule.period <= now() then 1 else l.hits + 1 end
    returning l.hits, l.window_start into used, started;
    if used > rule.max_requests then
      retry := greatest(1, ceil(extract(epoch from started + rule.period - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule.scope, rule.max_requests, rule.period),
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
  rule better_supabase.rate_limit_rules;
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from better_supabase.rate_limit_rules r where r.scope = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule.max_requests);
  limit_period := coalesce(period, rule.period);
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
  values (scope, key, now(), 1)
  on conflict on constraint rate_limits_pkey do update set
    window_start = case when l.window_start + limit_period <= now() then now() else l.window_start end,
    hits = case when l.window_start + limit_period <= now() then 1 else l.hits + 1 end
  returning l.hits, l.window_start into used, started;
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

-- Deletes up to batch counters whose window has ended, and counters without
-- a rule (removed rules, hit_rate_limit with its own limit) after a day.
-- Every caller keeps a row until then, so schedule it with pg_cron:
-- select cron.schedule('purge-rate-limits', '*/15 * * * *', 'select better_supabase.purge_rate_limits()');
create or replace function better_supabase.purge_rate_limits(batch integer default 10000)
returns integer
language sql
set search_path = ''
as $$
  with expired as (
    select l.scope, l.key from better_supabase.rate_limits l
    left join better_supabase.rate_limit_rules r on r.scope = l.scope
    where (r.scope is null and l.window_start < now() - interval '1 day')
      or l.window_start + r.period <= now()
    limit batch
  ),
  purged as (
    delete from better_supabase.rate_limits l
    using expired e
    where l.scope = e.scope and l.key = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
