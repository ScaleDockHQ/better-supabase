import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";

const RATE_LIMIT_HOOK = `-- Points PostgREST's pre-request hook at check_request. It keeps an
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
notify pgrst, 'reload config';`;

const RATE_LIMIT_NO_HOOK = `-- blocks.rate-limit.options.preRequest is false: the app calls
-- better_supabase.check_request() from its own pre-request function, or not
-- at all. Removes the setting when it still points at check_request.
do $$
begin
  if exists (
    select 1
    from pg_catalog.pg_db_role_setting s
    join pg_catalog.pg_roles r on r.oid = s.setrole
    cross join lateral unnest(s.setconfig) setting
    where r.rolname = 'authenticator' and s.setdatabase = 0
      and setting = 'pgrst.db_pre_request=better_supabase.check_request'
  ) then
    alter role authenticator reset pgrst.db_pre_request;
  end if;
end
$$;
notify pgrst, 'reload config';`;

const NAMES: BlockSqlNames = {
  options: ["preRequest"],
  tables: {
    rules: {
      name: "rate_limit_rules",
      app: { writes: false },
      columns: {
        scope: "scope",
        maxRequests: "max_requests",
        period: "period",
        keyClaim: "key_claim",
      },
    },
    counters: {
      name: "rate_limits",
      app: { writes: false },
      columns: {
        scope: "scope",
        key: "key",
        windowStart: "window_start",
        hits: "hits",
        period: "period",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  const rules = ctx.table("rules");
  const r = (column: string): string => ctx.col("rules", column);
  const counters = ctx.table("counters");
  const c = (column: string): string => ctx.col("counters", column);

  // Over the app's table the module's primary key isn't there.
  const counterKey = ctx.owns("counters")
    ? "on constraint rate_limits_pkey"
    : `(${c("scope")}, ${c("key")})`;

  const counterIndex = ctx.owns("counters")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("counters").name}_scope_key_key`)} on ${counters} (${c("scope")}, ${c("key")});`;

  // Over the app's table the module's primary key isn't there.
  const scopeIndex = ctx.owns("rules")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("rules").name}_scope_key`)} on ${rules} (${r("scope")});`;

  return `${schemaPreamble(ctx)}

-- One rule per scope: '*' (every write), a table path ('/customers') or an
-- RPC path ('/rpc/send_invite'). key_claim is the JWT claim each caller is
-- counted by; callers without it are counted by the right-most x-forwarded-for
-- hop, the one the API gateway appends. Clients can forge the hops before it.
create table if not exists ${rules} (
  ${r("scope")} text primary key,
  ${r("maxRequests")} integer not null check (${r("maxRequests")} > 0),
  ${r("period")} interval not null check (${r("period")} > interval '0'),
  ${r("keyClaim")} text not null default 'sub'
);${scopeIndex}

create unlogged table if not exists ${counters} (
  ${c("scope")} text not null,
  ${c("key")} text not null,
  ${c("windowStart")} timestamptz not null,
  ${c("hits")} integer not null,
  primary key (${c("scope")}, ${c("key")})
);${counterIndex}
-- The window length the counter was last hit with, so purge_rate_limits keeps
-- a counter for its whole window when no rule names its period.
alter table ${counters} add column if not exists ${c("period")} interval;

alter table ${rules} enable row level security;
alter table ${counters} enable row level security;
revoke all on table ${rules} from public, anon, authenticated;
revoke all on table ${counters} from public, anon, authenticated;

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
    delete from ${rules} r where r.${r("scope")} = set_rate_limit.scope;
    delete from ${counters} l where l.${c("scope")} = set_rate_limit.scope;
    return;
  end if;
  insert into ${rules} as r (${r("scope")}, ${r("maxRequests")}, ${r("period")}, ${r("keyClaim")})
  values (scope, max_requests, period, key_claim)
  on conflict (${r("scope")}) do update
    set ${r("maxRequests")} = excluded.${r("maxRequests")}, ${r("period")} = excluded.${r("period")}, ${r("keyClaim")} = excluded.${r("keyClaim")};
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
  rule ${rules};
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
    select * from ${rules} r where r.${r("scope")} in ('*', path) order by r.${r("scope")}
  loop
    caller := coalesce(
      claims ->> rule.${r("keyClaim")},
      'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown')
    );
    insert into ${counters} as l (${c("scope")}, ${c("key")}, ${c("windowStart")}, ${c("hits")}, ${c("period")})
    values (rule.${r("scope")}, caller, now(), 1, rule.${r("period")})
    on conflict ${counterKey} do update set
      ${c("windowStart")} = case when l.${c("windowStart")} + rule.${r("period")} <= now() then now() else l.${c("windowStart")} end,
      ${c("hits")} = case when l.${c("windowStart")} + rule.${r("period")} <= now() then 1 else l.${c("hits")} + 1 end,
      ${c("period")} = rule.${r("period")}
    returning l.${c("hits")}, l.${c("windowStart")} into used, started;
    if used > rule.${r("maxRequests")} then
      retry := greatest(1, ceil(extract(epoch from started + rule.${r("period")} - now()))::integer);
      raise sqlstate 'PGRST' using
        message = json_build_object(
          'code', 'BS429',
          'message', format('Rate limit for %s exceeded: %s writes per %s', rule.${r("scope")}, rule.${r("maxRequests")}, rule.${r("period")}),
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
  rule ${rules};
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from ${rules} r where r.${r("scope")} = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule.${r("maxRequests")});
  limit_period := coalesce(period, rule.${r("period")});
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into ${counters} as l (${c("scope")}, ${c("key")}, ${c("windowStart")}, ${c("hits")}, ${c("period")})
  values (scope, key, now(), 1, limit_period)
  on conflict ${counterKey} do update set
    ${c("windowStart")} = case when l.${c("windowStart")} + limit_period <= now() then now() else l.${c("windowStart")} end,
    ${c("hits")} = case when l.${c("windowStart")} + limit_period <= now() then 1 else l.${c("hits")} + 1 end,
    ${c("period")} = limit_period
  returning l.${c("hits")}, l.${c("windowStart")} into used, started;
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
  rule ${rules};
  counter ${counters};
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
    select * into rule from ${rules} r where r.${r("scope")} = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule.${r("maxRequests")});
    limit_period := coalesce((hit ->> 'period')::interval, rule.${r("period")});
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

  insert into ${counters} as l (${c("scope")}, ${c("key")}, ${c("windowStart")}, ${c("hits")}, ${c("period")})
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict ${counterKey} do nothing;

  perform 1
  from ${counters} l
  join unnest(scopes, keys) as u(scope, key) on l.${c("scope")} = u.scope and l.${c("key")} = u.key
  order by l.${c("scope")}, l.${c("key")}
  for update of l;

  for i in 1 .. total loop
    select * into counter from ${counters} l
    where l.${c("scope")} = scopes[i] and l.${c("key")} = keys[i];
    if counter.${c("windowStart")} + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter.${c("hits")};
      starts := starts || counter.${c("windowStart")};
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update ${counters} l set
        ${c("windowStart")} = starts[i],
        ${c("hits")} = used[i] + 1,
        ${c("period")} = periods[i]
      where l.${c("scope")} = scopes[i] and l.${c("key")} = keys[i];
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
    select l.${c("scope")}, l.${c("key")} from ${counters} l
    left join ${rules} r on r.${r("scope")} = l.${c("scope")}
    where l.${c("windowStart")} + coalesce(l.${c("period")}, r.${r("period")}, interval '1 day') <= now()
    limit batch
  ),
  purged as (
    delete from ${counters} l
    using expired e
    where l.${c("scope")} = e.scope and l.${c("key")} = e.key
    returning 1
  )
  select count(*)::integer from purged
$$;

revoke execute on function better_supabase.purge_rate_limits(integer) from public, anon, authenticated;
grant execute on function better_supabase.purge_rate_limits(integer) to service_role;`;
}

export const RATE_LIMIT: BlockSqlDefinition = {
  name: "rate-limit",
  names: NAMES,
  data: (ctx) =>
    ctx.flag("preRequest", true) ? RATE_LIMIT_HOOK : RATE_LIMIT_NO_HOOK,
  title: "Write rate limits",
  description:
    "Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.",
  requires: [],
  target: "schema",
  build,
};
