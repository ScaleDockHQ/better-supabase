import { sqlIdent } from "../core/template.ts";
import { postgresCacheNames } from "./names.ts";

export interface PostgresCacheSqlOptions {
  /** Default: `public`. */
  readonly schema?: string;
  /** Default: `bsb_cache_entries`. */
  readonly entriesTable?: string;
  /** Default: `bsb_cache_tags`. */
  readonly tagsTable?: string;
  /**
   * Prefix of the functions: `<prefix>_get` and `<prefix>_mark_tags`. Change it
   * when one schema holds two sets of cache tables. Default: `bsb_cache`.
   */
  readonly functionPrefix?: string;
  /**
   * Also schedule `pg_cron` to delete entries past their hard limit every hour.
   * Default: false.
   */
  readonly prune?: boolean;
}

const NOW_MS = "(extract(epoch from clock_timestamp()) * 1000)::bigint";

/**
 * The SQL for the tables and functions `postgresCacheStore` uses. Both tables
 * enable row level security with no policy, revoke every grant from `anon` and
 * `authenticated` and grant the service role, so only the service role reads or
 * writes them. Put it in a migration of your app; running it again on tables an
 * earlier release created adds what is new.
 */
export function postgresCacheSql(
  options: PostgresCacheSqlOptions = {},
): string {
  const names = postgresCacheNames(options);
  const schema = sqlIdent(names.schema);
  const entries = `${schema}.${sqlIdent(names.entriesTable)}`;
  const tags = `${schema}.${sqlIdent(names.tagsTable)}`;
  const getFn = `${schema}.${sqlIdent(names.getFunction)}`;
  const markFn = `${schema}.${sqlIdent(names.markTagsFunction)}`;

  const pruneJob = options.prune
    ? `
select cron.schedule(
  'bsb-cache-prune',
  '0 * * * *',
  $$delete from ${entries} where expires_at < ${NOW_MS}$$
);
`
    : "";

  return `create table if not exists ${entries} (
  key text primary key,
  value text not null,
  tags text[] not null default '{}',
  stored_at bigint not null,
  expires_at bigint not null,
  path text,
  meta jsonb not null default '{}'::jsonb
);

create index if not exists ${sqlIdent("bsb_cache_entries_expires_at_idx")} on ${entries} (expires_at);
create index if not exists ${sqlIdent("bsb_cache_entries_path_idx")} on ${entries} (path) where path is not null;

create table if not exists ${tags} (
  tag text primary key,
  stale_at bigint not null default 0,
  expired_at bigint not null default 0,
  expire_after bigint not null default 0
);

-- A delayed expiry has its own column, so an immediate one never replaces it.
alter table ${tags} add column if not exists expire_after bigint not null default 0;

alter table ${entries} enable row level security;
alter table ${tags} enable row level security;

revoke all on ${entries} from anon, authenticated;
revoke all on ${tags} from anon, authenticated;
grant select, insert, update, delete on ${entries} to service_role;
grant select, insert, update, delete on ${tags} to service_role;

-- One round trip per read: the entry, unless a tag of it or of the request
-- expired after it was stored, and whether one went stale.
create or replace function ${getFn}(
  p_key text,
  p_soft_tags text[] default '{}',
  p_now bigint default null
)
returns table (
  key text,
  value text,
  tags text[],
  stored_at bigint,
  expires_at bigint,
  path text,
  meta jsonb,
  stale boolean
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  with clock as (
    select coalesce(p_now, ${NOW_MS}) as now
  ),
  entry as (
    select e.key, e.value, e.tags, e.stored_at, e.expires_at, e.path, e.meta
    from ${entries} as e, clock
    where e.key = p_key and e.expires_at > clock.now
  ),
  states as (
    select t.stale_at, t.expired_at, t.expire_after
    from ${tags} as t, entry
    where t.tag = any(entry.tags || coalesce(p_soft_tags, '{}'))
  )
  select
    entry.key, entry.value, entry.tags, entry.stored_at, entry.expires_at,
    entry.path, entry.meta,
    exists (select 1 from states where states.stale_at > entry.stored_at)
  from entry, clock
  where not exists (
    select 1 from states
    where (states.expired_at > entry.stored_at and states.expired_at <= clock.now)
       or (states.expire_after > entry.stored_at and states.expire_after <= clock.now)
  )
$fn$;

-- One statement per call. Each column only moves forward (greatest), so
-- concurrent calls never undo each other. Rows are written in tag order, so two
-- calls over the same tags never deadlock.
create or replace function ${markFn}(
  p_tags text[],
  p_mode text default 'expire',
  p_expire_seconds bigint default 0,
  p_now bigint default null
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $fn$
  insert into ${tags} as t (tag, stale_at, expired_at, expire_after)
  select distinct
    u.tag,
    clock.now,
    case when p_mode = 'expire' then clock.now else 0 end,
    case when p_mode = 'delay' then clock.now + p_expire_seconds * 1000 else 0 end
  from unnest(p_tags) as u (tag),
    (select coalesce(p_now, ${NOW_MS}) as now) as clock
  order by 1
  on conflict (tag) do update set
    stale_at = greatest(t.stale_at, excluded.stale_at),
    expired_at = greatest(t.expired_at, excluded.expired_at),
    expire_after = greatest(t.expire_after, excluded.expire_after)
$fn$;

revoke all on function ${getFn}(text, text[], bigint) from public, anon, authenticated;
revoke all on function ${markFn}(text[], text, bigint, bigint) from public, anon, authenticated;
grant execute on function ${getFn}(text, text[], bigint) to service_role;
grant execute on function ${markFn}(text[], text, bigint, bigint) to service_role;
${pruneJob}`;
}
