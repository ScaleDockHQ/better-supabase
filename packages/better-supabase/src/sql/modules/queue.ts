import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { schemaPreamble, serviceOnly, revokeTable } from "../shared.ts";
import { MESSAGES_TABLE, table } from "./queue-table.ts";

export type JobsBackend = "pgmq" | "table";

export type JobsScheduler = "pg_cron" | "drain";

/** `blocks.queue.options.backend`: Supabase Queues (pgmq) or a plain table. */
function jobsBackend(ctx: BlockSqlContext): JobsBackend {
  const backend = ctx.text("backend", "pgmq");

  if (backend !== "pgmq" && backend !== "table") {
    throw new TypeError(
      `blocks.queue.options.backend must be "pgmq" or "table", not "${backend}"`,
    );
  }

  return backend;
}

/**
 * `blocks.queue.options.scheduler`: pg_cron, or due schedules run by the drain
 * route.
 */
function jobsScheduler(ctx: BlockSqlContext): JobsScheduler {
  const scheduler = ctx.text("scheduler", "pg_cron");

  if (scheduler !== "pg_cron" && scheduler !== "drain") {
    throw new TypeError(
      `blocks.queue.options.scheduler must be "pg_cron" or "drain", not "${scheduler}"`,
    );
  }

  return scheduler;
}

const LEGACY = `-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).
drop function if exists better_supabase.enqueue_job(text, jsonb, timestamptz, integer, text, integer);
-- enqueue_job before dedupe_running.
drop function if exists better_supabase.enqueue_job(text, jsonb, integer, integer, text);
drop function if exists better_supabase.claim_jobs(text, text, integer, interval);
drop function if exists better_supabase.complete_job(bigint, text);
drop function if exists better_supabase.fail_job(bigint, text, text, interval);
drop function if exists better_supabase.extend_job_lease(bigint, text, interval);
-- schedule_job before time zones.
drop function if exists better_supabase.schedule_job(text, text, text, jsonb);
-- purge_job_archive before dead letters had their own retention.
drop function if exists better_supabase.purge_job_archive(text, interval, integer);
-- schedule_job before schedules had a tenant.
drop function if exists better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz);
-- claim_due_schedules returns first_after now; create or replace can't change a return type.
drop function if exists better_supabase.claim_due_schedules(integer, integer);`;

/**
 * Opens purge_job_archive: nothing goes while a legal hold covers the archive,
 * and a data-lifecycle retention policy replaces both intervals.
 */
function archiveGuard(ctx: BlockSqlContext): string {
  const held = ctx.held("job_archive", "null");

  if (held === "false") {
    return "null;";
  }

  return `if ${held} then
    return 0;
  end if;
  older_than := ${ctx.retention("job_archive", "null", "older_than")};
  dead_older_than := ${ctx.retention("job_archive", "null", "dead_older_than")};`;
}

const pgmq = (
  guard: string,
): string => `-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table and its archive (enqueue_job_once) get a partial index on it.
create or replace function better_supabase.index_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'create index if not exists %I on pgmq.%I ((message ->> ''dedupe_key'')) where message ? ''dedupe_key''',
    'q_' || queue || '_dedupe_idx',
    'q_' || queue
  );
  execute format(
    'create index if not exists %I on pgmq.%I ((message ->> ''dedupe_key'')) where message ? ''dedupe_key''',
    'a_' || queue || '_dedupe_idx',
    'a_' || queue
  );
end;
$$;

-- Queue names: lowercase letters, digits and underscores (pgmq's rule).
create or replace function better_supabase.ensure_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
    perform pgmq.create(queue);
    perform better_supabase.index_job_queue(queue);
  end if;
end;
$$;

-- While a message with dedupe_key is waiting or running, enqueueing again
-- returns its id. With dedupe_running false only a message no worker has
-- claimed yet counts, so a change made during a run queues one follow-up.
create or replace function better_supabase.enqueue_job(
  queue text,
  payload jsonb default '{}',
  delay integer default 0,
  max_attempts integer default 5,
  dedupe_key text default null,
  dedupe_running boolean default true
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing bigint;
begin
  perform better_supabase.ensure_job_queue(queue);
  if dedupe_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
    execute format('select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 and ($2 or read_ct = 0) limit 1', 'q_' || queue)
      into existing using dedupe_key, dedupe_running;
    if existing is not null then
      return existing;
    end if;
  end if;
  return (
    select pgmq.send(
      queue,
      jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
        || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
      greatest(delay, 0)
    )
  );
end;
$$;

-- Enqueues once per dedupe_key: while a message with the key is waiting,
-- running or still archived (until purge_job_archive removes it), returns
-- its id with duplicate true instead.
create or replace function better_supabase.enqueue_job_once(
  queue text,
  payload jsonb,
  dedupe_key text,
  delay integer default 0,
  max_attempts integer default 5
)
returns table (id bigint, duplicate boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing bigint;
begin
  if dedupe_key is null then
    raise exception 'enqueue_job_once needs a dedupe_key' using errcode = '22004';
  end if;
  perform better_supabase.ensure_job_queue(queue);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
  execute format('select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 union all select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 limit 1', 'q_' || queue, 'a_' || queue)
    into existing using dedupe_key;
  if existing is not null then
    id := existing;
    duplicate := true;
  else
    id := better_supabase.enqueue_job(queue, payload, delay, max_attempts, dedupe_key);
    duplicate := false;
  end if;
  return next;
end;
$$;

-- A message read past max_attempts lost its worker on the last attempt
-- (fail_job archives it otherwise), so the claim archives it as dead.
create or replace function better_supabase.claim_jobs(queue text, lease integer default 300, batch integer default 1)
returns table (id bigint, attempts integer, enqueued_at timestamptz, visible_until timestamptz, message jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  dead bigint[] := '{}';
begin
  perform better_supabase.ensure_job_queue(queue);
  for r in select * from pgmq.read(queue, lease, batch) loop
    if r.read_ct > coalesce((r.message ->> 'max_attempts')::integer, 5) then
      dead := dead || r.msg_id;
    else
      id := r.msg_id;
      attempts := r.read_ct;
      enqueued_at := r.enqueued_at;
      visible_until := r.vt;
      message := r.message;
      return next;
    end if;
  end loop;
  if cardinality(dead) > 0 then
    execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', ''The lease ran out on the last attempt'', ''dead'', true) where msg_id = any ($1)', 'q_' || queue)
      using dead;
    perform pgmq.archive(queue, dead);
  end if;
end;
$$;

-- Each claim bumps read_ct, so a stale worker (its lease expired and another
-- worker claimed the message) no longer matches and gets false / null.
create or replace function better_supabase.complete_job(queue text, job_id bigint, attempt integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  return pgmq.archive(queue, job_id);
end;
$$;

-- Retries with exponential backoff and full jitter (a random wait up to 10s,
-- 20s, 40s, ... at most an hour) until max_attempts, then archives the
-- message with dead = true.
create or replace function better_supabase.fail_job(
  queue text,
  job_id bigint,
  attempt integer,
  error text,
  retry_in integer default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg jsonb;
begin
  execute format('select message from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into msg using job_id, attempt;
  if msg is null then
    return null;
  end if;
  if attempt >= coalesce((msg ->> 'max_attempts')::integer, 5) then
    execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text, ''dead'', true) where msg_id = $1', 'q_' || queue)
      using job_id, left(error, 4000);
    perform pgmq.archive(queue, job_id);
    return 'dead';
  end if;
  execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text), vt = clock_timestamp() + make_interval(secs => $3) where msg_id = $1', 'q_' || queue)
    using job_id, left(error, 4000), coalesce(retry_in, 1 + floor(random() * least(3600, 10 * power(2, attempt - 1)))::integer);
  return 'queued';
end;
$$;

create or replace function better_supabase.extend_job_lease(queue text, job_id bigint, attempt integer, lease integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  perform pgmq.set_vt(queue, job_id, lease);
  return true;
end;
$$;

-- pgmq keeps completed and dead messages in pgmq.a_<queue>. Deletes up to
-- batch of them archived longer than older_than, or dead_older_than for dead
-- letters, which are kept longer so they can be replayed.
create or replace function better_supabase.purge_job_archive(
  queue text,
  older_than interval default '7 days',
  batch integer default 10000,
  dead_older_than interval default '30 days'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purged integer;
begin
  ${guard}
  execute format(
    'with purged as (delete from pgmq.%1$I where msg_id in (select a.msg_id from pgmq.%1$I a where a.archived_at < now() - case when a.message ? ''dead'' then $3 else $1 end order by a.msg_id limit $2) returning 1) select count(*)::integer from purged',
    'a_' || queue
  ) into purged using older_than, batch, dead_older_than;
  return purged;
end;
$$;

-- Enqueues a dead letter again with its payload, attempts and dedupe key,
-- and removes it from the archive. Returns the new id, or null when job_id
-- is not a dead letter of the queue.
create or replace function better_supabase.replay_dead_job(queue text, job_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg jsonb;
begin
  perform better_supabase.ensure_job_queue(queue);
  execute format('delete from pgmq.%I where msg_id = $1 and message ? ''dead'' returning message', 'a_' || queue)
    into msg using job_id;
  if msg is null then
    return null;
  end if;
  return better_supabase.enqueue_job(
    queue,
    coalesce(msg -> 'payload', '{}'),
    0,
    coalesce((msg ->> 'max_attempts')::integer, 5),
    msg ->> 'dedupe_key'
  );
end;
$$;

-- Counts for an admin page: ready (visible now), in flight (claimed, or
-- waiting out a retry backoff), delayed (enqueued for later, never claimed),
-- dead letters, and the age of the oldest message not yet done.
create or replace function better_supabase.job_queue_stats(queue text)
returns table (ready bigint, in_flight bigint, delayed bigint, dead bigint, oldest_age_seconds double precision)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
    return query select 0::bigint, 0::bigint, 0::bigint, 0::bigint, null::double precision;
    return;
  end if;
  return query execute format(
    'select count(*) filter (where q.vt <= clock_timestamp()),
       count(*) filter (where q.vt > clock_timestamp() and q.read_ct > 0),
       count(*) filter (where q.vt > clock_timestamp() and q.read_ct = 0),
       (select count(*) from pgmq.%2$I a where a.message ? ''dead''),
       extract(epoch from clock_timestamp() - min(q.enqueued_at))::double precision
     from pgmq.%1$I q',
    'q_' || queue, 'a_' || queue
  );
end;
$$;

-- A queue's dead letters, newest first, before before_id when given.
create or replace function better_supabase.list_dead_jobs(queue text, max_rows integer default 100, before_id bigint default null)
returns table (id bigint, attempts integer, enqueued_at timestamptz, died_at timestamptz, message jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'a_' || queue)) is null then
    return;
  end if;
  return query execute format(
    'select a.msg_id, a.read_ct, a.enqueued_at, a.archived_at, a.message from pgmq.%I a
     where a.message ? ''dead'' and ($2 is null or a.msg_id < $2)
     order by a.msg_id desc limit least(greatest($1, 1), 1000)',
    'a_' || queue
  ) using max_rows, before_id;
end;
$$;

-- Enqueues dead letters again: the ids given, or the newest batch of them.
-- Returns how many went back on the queue.
create or replace function better_supabase.retry_dead_jobs(queue text, ids bigint[] default null, batch integer default 1000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  dead_id bigint;
  retried integer := 0;
begin
  for dead_id in
    select d.id from better_supabase.list_dead_jobs(queue, batch) d where ids is null
    union all
    select unnest(ids) where ids is not null
  loop
    if better_supabase.replay_dead_job(queue, dead_id) is not null then
      retried := retried + 1;
    end if;
  end loop;
  return retried;
end;
$$;`;

const ensureQueue = (backend: JobsBackend): string =>
  backend === "pgmq"
    ? "\n  perform better_supabase.ensure_job_queue(queue);"
    : "";

const PG_CRON = (
  backend: JobsBackend,
) => `-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
-- select better_supabase.schedule_job('nightly-digest', '0 3 * * *', 'emails', '{"kind": "digest"}');
-- For another time zone or a tenant per schedule, set
-- blocks.queue.options.scheduler to "drain".
create or replace function better_supabase.schedule_job(
  job_name text,
  schedule text,
  queue text,
  payload jsonb default '{}',
  timezone text default 'UTC',
  next_run timestamptz default null,
  tenant text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- pg_cron is optional: its functions are looked up, not named, so
  -- plpgsql_check (supabase db lint) passes without the extension.
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
  v_id bigint;
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set blocks.queue.options.scheduler to "drain" to keep one per schedule';
  end if;
  if v_schedule is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set blocks.queue.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set blocks.queue.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;${ensureQueue(backend)}
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text);
  return v_id;
end;
$$;

create or replace function better_supabase.unschedule_job(job_name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unschedule regprocedure := pg_catalog.to_regprocedure('cron.unschedule(text)');
  v_removed boolean;
begin
  if v_unschedule is null then
    return false;
  end if;
  execute format('select %s($1::text)', v_unschedule::oid::regproc)
    into v_removed
    using job_name;
  return v_removed;
end;
$$;

-- pg_cron enqueues the runs itself, so the drain route has no schedules to claim.
create or replace function better_supabase.claim_due_schedules(lease integer default 60, batch integer default 100)
returns table (job_name text, schedule text, timezone text, queue text, payload jsonb, next_run timestamptz, first_after timestamptz)
language sql
security definer
set search_path = ''
as $$
  select null::text, null::text, null::text, null::text, null::jsonb, null::timestamptz, null::timestamptz where false;
$$;

create or replace function better_supabase.advance_schedule(job_name text, ran timestamptz, next_run timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select false;
$$;

-- pg_cron's jobs whose name starts with name_prefix. pg_cron keeps no queue,
-- tenant or next run, so those are null.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, locked_until timestamptz, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
begin
  if v_jobs is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute format(
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz
     from %s j where $1 is null or starts_with(j.jobname, $1) order by j.jobname', v_jobs)
    using name_prefix;
end;
$$;

-- pg_cron schedules have no tenant, so there is nothing to remove.
create or replace function better_supabase.unschedule_tenant(tenant text)
returns integer
language sql
security definer
set search_path = ''
as $$
  select 0;
$$;`;

function drain(ctx: BlockSqlContext): string {
  const schedules = ctx.table("schedules");
  const c = (column: string): string => ctx.col("schedules", column);
  const { name } = ctx.tableName("schedules");
  const index = (what: string): string => sqlIdent(`${name}_${what}`);

  // Before first_after, every schedule had a next run.
  const legacy = ctx.owns("schedules")
    ? `\nalter table ${schedules} alter column ${c("nextRun")} drop not null;`
    : "";

  const jobNameKey = ctx.owns("schedules")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${name}_job_name_key`)} on ${schedules} (${c("jobName")});`;

  return `-- Recurring jobs without pg_cron: the drain route (jobs.drainRoute) claims due
-- schedules, enqueues a run and moves next_run on. Times are computed in
-- TypeScript, in each schedule's time zone. A schedule written in SQL without a
-- next run (a trigger calling schedule_job) keeps next_run null and first_after
-- set, and the next drain computes its first run after first_after.
create table if not exists ${schedules} (
  ${c("jobName")} text primary key,
  ${c("schedule")} text not null,
  ${c("timezone")} text not null default 'UTC',
  ${c("queue")} text not null,
  ${c("payload")} jsonb not null default '{}',
  ${c("nextRun")} timestamptz not null,
  ${c("lastRun")} timestamptz,
  ${c("lockedUntil")} timestamptz,
  ${c("createdAt")} timestamptz not null default now()
);
-- The tenant a schedule runs for, so a tenant's schedules can be listed and
-- removed together (unschedule_tenant).
alter table ${schedules} add column if not exists ${c("tenant")} text;
alter table ${schedules} add column if not exists ${c("firstAfter")} timestamptz;${legacy}${jobNameKey}
create index if not exists ${index("due_idx")} on ${schedules} (${c("nextRun")});
create index if not exists ${index("tenant_idx")} on ${schedules} (${c("tenant")}) where ${c("tenant")} is not null;
alter table ${schedules} enable row level security;
${revokeTable(schedules)}

-- jobs.schedule passes the next cron time. Without next_run, the next drain
-- computes the first run after now. Writing a schedule again with the same
-- cron and time zone keeps its next run, so a run that is due but not yet
-- drained still happens.
create or replace function better_supabase.schedule_job(
  job_name text,
  schedule text,
  queue text,
  payload jsonb default '{}',
  timezone text default 'UTC',
  next_run timestamptz default null,
  tenant text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = timezone) then
    raise exception 'Unknown time zone %', timezone;
  end if;
  if schedule !~* '^[[:space:]]*(@(yearly|annually|monthly|weekly|daily|midnight|hourly)|[0-9]+[[:space:]]+(second|minute|hour)s?|[^[:space:]]+([[:space:]]+[^[:space:]]+){4})[[:space:]]*$' then
    raise exception 'Invalid schedule %: expected five cron fields, a macro such as @daily, or an interval such as 5 minutes', schedule
      using errcode = '22023';
  end if;
  insert into ${schedules} as s (${c("jobName")}, ${c("schedule")}, ${c("timezone")}, ${c("queue")}, ${c("payload")}, ${c("nextRun")}, ${c("firstAfter")}, ${c("tenant")})
  values (job_name, schedule, timezone, queue, payload, date_trunc('milliseconds', next_run),
    case when next_run is null then date_trunc('milliseconds', now()) end, tenant)
  on conflict (${c("jobName")}) do update
    set ${c("schedule")} = excluded.${c("schedule")},
        ${c("timezone")} = excluded.${c("timezone")},
        ${c("queue")} = excluded.${c("queue")},
        ${c("payload")} = excluded.${c("payload")},
        ${c("nextRun")} = case
          when s.${c("schedule")} = excluded.${c("schedule")} and s.${c("timezone")} = excluded.${c("timezone")}
            then s.${c("nextRun")}
          else excluded.${c("nextRun")}
        end,
        ${c("firstAfter")} = case
          when s.${c("schedule")} = excluded.${c("schedule")} and s.${c("timezone")} = excluded.${c("timezone")}
            then s.${c("firstAfter")}
          else excluded.${c("firstAfter")}
        end,
        ${c("tenant")} = excluded.${c("tenant")},
        ${c("lockedUntil")} = null;
  return null;
end;
$$;

-- Schedules whose name starts with name_prefix and that run for for_tenant (either
-- filter null: all), for a product page that shows the next run.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, locked_until timestamptz, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select s.${c("jobName")}, s.${c("schedule")}, s.${c("timezone")}, s.${c("queue")}, s.${c("tenant")}, s.${c("nextRun")}, s.${c("lastRun")}, s.${c("lockedUntil")}, s.${c("createdAt")}
  from ${schedules} s
  where (list_schedules.name_prefix is null or starts_with(s.${c("jobName")}, list_schedules.name_prefix))
    and (list_schedules.for_tenant is null or s.${c("tenant")} = list_schedules.for_tenant)
  order by s.${c("jobName")};
$$;

-- Removes every schedule of a tenant, for tenant deletion. Returns how many.
create or replace function better_supabase.unschedule_tenant(tenant text)
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from ${schedules} s where s.${c("tenant")} = unschedule_tenant.tenant returning 1
  )
  select count(*)::integer from removed;
$$;

create or replace function better_supabase.unschedule_job(job_name text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from ${schedules} s where s.${c("jobName")} = unschedule_job.job_name returning 1
  )
  select exists (select 1 from removed);
$$;

-- Leases due schedules for lease seconds, so concurrent drains don't run one twice.
-- A schedule without a next run is claimed so the drain computes its first run.
create or replace function better_supabase.claim_due_schedules(lease integer default 60, batch integer default 100)
returns table (job_name text, schedule text, timezone text, queue text, payload jsonb, next_run timestamptz, first_after timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
    with due as (
      select s.${c("jobName")} as job_name
      from ${schedules} s
      where (s.${c("nextRun")} is null or s.${c("nextRun")} <= clock_timestamp())
        and (s.${c("lockedUntil")} is null or s.${c("lockedUntil")} < clock_timestamp())
      order by s.${c("nextRun")} nulls first
      limit greatest(batch, 1)
      for update skip locked
    )
    update ${schedules} s
    set ${c("lockedUntil")} = clock_timestamp() + make_interval(secs => lease)
    from due
    where s.${c("jobName")} = due.job_name
    returning s.${c("jobName")}, s.${c("schedule")}, s.${c("timezone")}, s.${c("queue")}, s.${c("payload")}, s.${c("nextRun")}, s.${c("firstAfter")};
end;
$$;

-- Moves a schedule on after its run was enqueued. Times are kept to the
-- millisecond, the precision JavaScript reads them back with. A schedule
-- without a next run takes its first one (ran is null when nothing ran).
-- False when it was rescheduled or another drain advanced it since the claim.
create or replace function better_supabase.advance_schedule(job_name text, ran timestamptz, next_run timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with advanced as (
    update ${schedules} s
    set ${c("nextRun")} = date_trunc('milliseconds', advance_schedule.next_run),
        ${c("lastRun")} = coalesce(ran, s.${c("lastRun")}),
        ${c("firstAfter")} = null,
        ${c("lockedUntil")} = null
    where s.${c("jobName")} = advance_schedule.job_name
      and (
        date_trunc('milliseconds', s.${c("nextRun")}) = date_trunc('milliseconds', ran)
        or (s.${c("nextRun")} is null and s.${c("firstAfter")} is not null)
      )
    returning 1
  )
  select exists (select 1 from advanced);
$$;`;
}

const GRANTS = (backend: JobsBackend): string =>
  serviceOnly([
    ...(backend === "pgmq"
      ? ["index_job_queue(text)", "ensure_job_queue(text)"]
      : []),
    "enqueue_job(text, jsonb, integer, integer, text, boolean)",
    "enqueue_job_once(text, jsonb, text, integer, integer)",
    "claim_jobs(text, integer, integer)",
    "complete_job(text, bigint, integer)",
    "fail_job(text, bigint, integer, text, integer)",
    "extend_job_lease(text, bigint, integer, integer)",
    "schedule_job(text, text, text, jsonb, text, timestamptz, text)",
    "unschedule_job(text)",
    "list_schedules(text, text)",
    "unschedule_tenant(text)",
    "claim_due_schedules(integer, integer)",
    "advance_schedule(text, timestamptz, timestamptz)",
    "purge_job_archive(text, interval, integer, interval)",
    "replay_dead_job(text, bigint)",
    "job_queue_stats(text)",
    "list_dead_jobs(text, integer, bigint)",
    "retry_dead_jobs(text, bigint[], integer)",
  ]);

// Both tables exist only with their option: messages with backend "table",
// schedules with scheduler "drain". pgmq keeps its own per-queue tables.
const NAMES: BlockSqlNames = {
  options: ["backend", "scheduler"],
  tables: {
    messages: MESSAGES_TABLE,
    schedules: {
      name: "job_schedules",
      app: { writes: false },
      columns: {
        jobName: "job_name",
        schedule: "schedule",
        timezone: "timezone",
        queue: "queue",
        payload: "payload",
        nextRun: "next_run",
        lastRun: "last_run",
        lockedUntil: "locked_until",
        createdAt: "created_at",
        tenant: "tenant",
        firstAfter: "first_after",
      },
    },
  },
};

function jobsSql(ctx: BlockSqlContext): string {
  const backend = jobsBackend(ctx);
  const scheduler = jobsScheduler(ctx);

  return [
    schemaPreamble(ctx),
    LEGACY,
    backend === "pgmq"
      ? pgmq(archiveGuard(ctx))
      : table(ctx, archiveGuard(ctx)),
    scheduler === "pg_cron" ? PG_CRON(backend) : drain(ctx),
    GRANTS(backend),
  ].join("\n\n");
}

export const JOBS: BlockSqlDefinition = {
  name: "queue",
  title: "Job queue",
  description:
    "Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.",
  requires: [],
  integrates: ["data-lifecycle"],
  target: "schema",
  version: 8,
  names: NAMES,
  data: (ctx) =>
    jobsBackend(ctx) === "pgmq"
      ? "-- Indexes the queues that existed before the module.\nselect better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;"
      : "",
  upgrades: [
    {
      from: 1,
      description:
        "schedule_job takes a time zone and next run; the drain scheduler and the table backend are options.",
      sql: () =>
        "drop function if exists better_supabase.schedule_job(text, text, text, jsonb);",
    },
    {
      from: 2,
      description:
        "Dead letters get their own retention in purge_job_archive and replay_dead_job; claims archive a message whose last attempt lost its worker.",
      sql: () =>
        "drop function if exists better_supabase.purge_job_archive(text, interval, integer);",
    },
    {
      from: 3,
      description:
        "Schedules record a tenant (job_schedules.tenant); list_schedules and unschedule_tenant list and remove them.",
      sql: () =>
        "drop function if exists better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz);",
    },
    {
      from: 4,
      description:
        "A schedule written in SQL without a next run gets its first run from the drain; claim_due_schedules returns first_after.",
      sql: () =>
        "drop function if exists better_supabase.claim_due_schedules(integer, integer);",
    },
    {
      from: 5,
      description:
        "The table backend stores max_attempts as a generated column with an index for lost leases, and claims compare visible_at with one timestamp.",
      sql: () => "",
    },
    {
      from: 6,
      description:
        "enqueue_job_once enqueues once per dedupe key, including archived messages, and reports a duplicate.",
      sql: () => "",
    },
    {
      from: 7,
      description:
        "purge_job_archive keeps the archive for the data-lifecycle retention policy and purges nothing under a legal hold.",
      sql: () => "",
    },
  ],
  build: jobsSql,
};
