import type { ModuleContext } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { SCHEMA, serviceOnly } from "../shared.ts";

export type JobsBackend = "pgmq" | "table";
export type JobsScheduler = "pg_cron" | "drain";

/** `sql.modules.jobs.options.backend`: Supabase Queues (pgmq) or a plain table. */
function jobsBackend(ctx: ModuleContext): JobsBackend {
  const backend = ctx.text("backend", "pgmq");
  if (backend !== "pgmq" && backend !== "table") {
    throw new TypeError(
      `sql.modules.jobs.options.backend must be "pgmq" or "table", not "${backend}"`,
    );
  }
  return backend;
}

/** `sql.modules.jobs.options.scheduler`: pg_cron, or due schedules run by the drain route. */
function jobsScheduler(ctx: ModuleContext): JobsScheduler {
  const scheduler = ctx.text("scheduler", "pg_cron");
  if (scheduler !== "pg_cron" && scheduler !== "drain") {
    throw new TypeError(
      `sql.modules.jobs.options.scheduler must be "pg_cron" or "drain", not "${scheduler}"`,
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

const PGMQ = `-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table gets a partial index on it.
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
begin
  perform better_supabase.ensure_job_queue(queue);
  for r in select * from pgmq.read(queue, lease, batch) loop
    if r.read_ct > coalesce((r.message ->> 'max_attempts')::integer, 5) then
      execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', ''The lease ran out on the last attempt'', ''dead'', true) where msg_id = $1', 'q_' || queue)
        using r.msg_id;
      perform pgmq.archive(queue, r.msg_id);
    else
      id := r.msg_id;
      attempts := r.read_ct;
      enqueued_at := r.enqueued_at;
      visible_until := r.vt;
      message := r.message;
      return next;
    end if;
  end loop;
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

const TABLE = `-- Jobs in a plain table, for projects without pgmq. Messages have the same
-- {payload, max_attempts, dedupe_key?, last_error?} body as on pgmq; claims
-- take rows with for update skip locked, and attempts is the lease token.
create table if not exists better_supabase.job_messages (
  id bigint generated always as identity primary key,
  queue text not null check (queue ~ '^[a-z_][a-z0-9_]{0,46}$'),
  message jsonb not null,
  attempts integer not null default 0,
  enqueued_at timestamptz not null default now(),
  visible_at timestamptz not null default now(),
  archived_at timestamptz,
  dead boolean not null default false,
  dedupe_key text generated always as (message ->> 'dedupe_key') stored
);
create index if not exists job_messages_ready_idx
  on better_supabase.job_messages (queue, visible_at) where archived_at is null;
-- One waiting message per dedupe key; a claimed one can have a follow-up
-- queued behind it (enqueue_job with dedupe_running false).
drop index if exists better_supabase.job_messages_dedupe_idx;
create unique index if not exists job_messages_waiting_dedupe_idx
  on better_supabase.job_messages (queue, dedupe_key) where archived_at is null and dedupe_key is not null and attempts = 0;
create index if not exists job_messages_dedupe_lookup_idx
  on better_supabase.job_messages (queue, dedupe_key) where archived_at is null and dedupe_key is not null;
create index if not exists job_messages_archived_idx
  on better_supabase.job_messages (queue, archived_at) where archived_at is not null;
-- The message's attempt limit as a column, so claims find messages whose
-- lease ran out on the last attempt through an index.
alter table better_supabase.job_messages add column if not exists max_attempts integer
  generated always as (coalesce((message ->> 'max_attempts')::integer, 5)) stored;
create index if not exists job_messages_exhausted_idx
  on better_supabase.job_messages (queue, visible_at) where archived_at is null and attempts >= max_attempts;
alter table better_supabase.job_messages enable row level security;
revoke all on better_supabase.job_messages from anon, authenticated;

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
  created bigint;
begin
  if dedupe_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
    select m.id into existing
    from better_supabase.job_messages m
    where m.queue = enqueue_job.queue and m.dedupe_key = enqueue_job.dedupe_key and m.archived_at is null
      and (enqueue_job.dedupe_running or m.attempts = 0)
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into better_supabase.job_messages (queue, message, visible_at)
  values (
    queue,
    jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
      || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
    clock_timestamp() + make_interval(secs => greatest(delay, 0))
  )
  returning id into created;
  return created;
end;
$$;

create or replace function better_supabase.claim_jobs(queue text, lease integer default 300, batch integer default 1)
returns table (id bigint, attempts integer, enqueued_at timestamptz, visible_until timestamptz, message jsonb)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  -- A variable, not clock_timestamp() in the where clause, so visible_at is
  -- an index condition.
  v_now timestamptz := clock_timestamp();
begin
  -- A visible message at max_attempts lost its worker on the last attempt
  -- (fail_job archives it otherwise).
  update better_supabase.job_messages m
  set message = m.message || jsonb_build_object('last_error', 'The lease ran out on the last attempt', 'dead', true),
      dead = true,
      archived_at = now()
  where m.queue = claim_jobs.queue and m.archived_at is null and m.visible_at <= v_now
    and m.attempts >= m.max_attempts;
  return query
    with picked as (
      select m.id
      from better_supabase.job_messages m
      where m.queue = claim_jobs.queue and m.archived_at is null and m.visible_at <= v_now
      order by m.visible_at, m.id
      limit greatest(batch, 1)
      for update skip locked
    )
    update better_supabase.job_messages m
    set attempts = m.attempts + 1,
        visible_at = v_now + make_interval(secs => lease)
    from picked
    where m.id = picked.id
    returning m.id, m.attempts, m.enqueued_at, m.visible_at, m.message;
end;
$$;

-- Each claim bumps attempts, so a stale worker (its lease expired and another
-- worker claimed the message) no longer matches and gets false / null.
create or replace function better_supabase.complete_job(queue text, job_id bigint, attempt integer)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with done as (
    update better_supabase.job_messages m
    set archived_at = now()
    where m.id = job_id and m.queue = complete_job.queue and m.attempts = attempt and m.archived_at is null
    returning 1
  )
  select exists (select 1 from done);
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
  select m.message into msg
  from better_supabase.job_messages m
  where m.id = job_id and m.queue = fail_job.queue and m.attempts = attempt and m.archived_at is null
  for update;
  if msg is null then
    return null;
  end if;
  if attempt >= coalesce((msg ->> 'max_attempts')::integer, 5) then
    update better_supabase.job_messages m
    set message = m.message || jsonb_build_object('last_error', left(error, 4000), 'dead', true),
        dead = true,
        archived_at = now()
    where m.id = job_id;
    return 'dead';
  end if;
  update better_supabase.job_messages m
  set message = m.message || jsonb_build_object('last_error', left(error, 4000)),
      visible_at = clock_timestamp() + make_interval(secs => coalesce(retry_in, 1 + floor(random() * least(3600, 10 * power(2, attempt - 1)))::integer))
  where m.id = job_id;
  return 'queued';
end;
$$;

create or replace function better_supabase.extend_job_lease(queue text, job_id bigint, attempt integer, lease integer)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with extended as (
    update better_supabase.job_messages m
    set visible_at = clock_timestamp() + make_interval(secs => lease)
    where m.id = job_id and m.queue = extend_job_lease.queue and m.attempts = attempt and m.archived_at is null
    returning 1
  )
  select exists (select 1 from extended);
$$;

-- Completed and dead messages stay in job_messages with archived_at. Deletes
-- up to batch of them archived longer than older_than, or dead_older_than
-- for dead letters, which are kept longer so they can be replayed.
create or replace function better_supabase.purge_job_archive(
  queue text,
  older_than interval default '7 days',
  batch integer default 10000,
  dead_older_than interval default '30 days'
)
returns integer
language sql
security definer
set search_path = ''
as $$
  with purged as (
    delete from better_supabase.job_messages
    where id in (
      select m.id from better_supabase.job_messages m
      where m.queue = purge_job_archive.queue
        and m.archived_at < now() - least(older_than, dead_older_than)
        and m.archived_at < now() - case when m.dead then dead_older_than else older_than end
      order by m.id
      limit batch
    )
    returning 1
  )
  select count(*)::integer from purged;
$$;

-- Enqueues a dead letter again with its payload, attempts and dedupe key,
-- and removes the dead row. Returns the new id, or null when job_id is not a
-- dead letter of the queue.
create or replace function better_supabase.replay_dead_job(queue text, job_id bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  msg jsonb;
begin
  delete from better_supabase.job_messages m
  where m.id = job_id and m.queue = replay_dead_job.queue and m.dead
  returning m.message into msg;
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
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*) filter (where m.archived_at is null and m.visible_at <= clock_timestamp()),
    count(*) filter (where m.archived_at is null and m.visible_at > clock_timestamp() and m.attempts > 0),
    count(*) filter (where m.archived_at is null and m.visible_at > clock_timestamp() and m.attempts = 0),
    count(*) filter (where m.dead),
    extract(epoch from clock_timestamp() - min(m.enqueued_at) filter (where m.archived_at is null))::double precision
  from better_supabase.job_messages m
  where m.queue = job_queue_stats.queue;
$$;

-- A queue's dead letters, newest first, before before_id when given.
create or replace function better_supabase.list_dead_jobs(queue text, max_rows integer default 100, before_id bigint default null)
returns table (id bigint, attempts integer, enqueued_at timestamptz, died_at timestamptz, message jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.attempts, m.enqueued_at, m.archived_at, m.message
  from better_supabase.job_messages m
  where m.queue = list_dead_jobs.queue and m.dead
    and (before_id is null or m.id < before_id)
  order by m.id desc
  limit least(greatest(max_rows, 1), 1000);
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
-- sql.modules.jobs.options.scheduler to "drain".
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
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set sql.modules.jobs.options.scheduler to "drain" to keep one per schedule';
  end if;
  if pg_catalog.to_regnamespace('cron') is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set sql.modules.jobs.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set sql.modules.jobs.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;${ensureQueue(backend)}
  return cron.schedule(job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text));
end;
$$;

create or replace function better_supabase.unschedule_job(job_name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_catalog.to_regnamespace('cron') is null then
    return false;
  end if;
  return cron.unschedule(job_name);
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
begin
  if pg_catalog.to_regnamespace('cron') is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz
     from cron.job j where $1 is null or starts_with(j.jobname, $1) order by j.jobname'
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

const DRAIN = `-- Recurring jobs without pg_cron: the drain route (jobs.drainRoute) claims due
-- schedules, enqueues a run and moves next_run on. Times are computed in
-- TypeScript, in each schedule's time zone. A schedule written in SQL without a
-- next run (a trigger calling schedule_job) keeps next_run null and first_after
-- set, and the next drain computes its first run after first_after.
create table if not exists better_supabase.job_schedules (
  job_name text primary key,
  schedule text not null,
  timezone text not null default 'UTC',
  queue text not null,
  payload jsonb not null default '{}',
  next_run timestamptz not null,
  last_run timestamptz,
  locked_until timestamptz,
  created_at timestamptz not null default now()
);
-- The tenant a schedule runs for, so a tenant's schedules can be listed and
-- removed together (unschedule_tenant).
alter table better_supabase.job_schedules add column if not exists tenant text;
alter table better_supabase.job_schedules add column if not exists first_after timestamptz;
alter table better_supabase.job_schedules alter column next_run drop not null;
create index if not exists job_schedules_due_idx on better_supabase.job_schedules (next_run);
create index if not exists job_schedules_tenant_idx on better_supabase.job_schedules (tenant) where tenant is not null;
alter table better_supabase.job_schedules enable row level security;
revoke all on better_supabase.job_schedules from anon, authenticated;

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
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = timezone) then
    raise exception 'Unknown time zone %', timezone;
  end if;
  if schedule !~* '^[[:space:]]*(@(yearly|annually|monthly|weekly|daily|midnight|hourly)|[0-9]+[[:space:]]+(second|minute|hour)s?|[^[:space:]]+([[:space:]]+[^[:space:]]+){4})[[:space:]]*$' then
    raise exception 'Invalid schedule %: expected five cron fields, a macro such as @daily, or an interval such as 5 minutes', schedule
      using errcode = '22023';
  end if;
  insert into better_supabase.job_schedules (job_name, schedule, timezone, queue, payload, next_run, first_after, tenant)
  values (job_name, schedule, timezone, queue, payload, date_trunc('milliseconds', next_run),
    case when next_run is null then date_trunc('milliseconds', now()) end, tenant)
  on conflict on constraint job_schedules_pkey do update
    set schedule = excluded.schedule,
        timezone = excluded.timezone,
        queue = excluded.queue,
        payload = excluded.payload,
        next_run = case
          when job_schedules.schedule = excluded.schedule and job_schedules.timezone = excluded.timezone
            then job_schedules.next_run
          else excluded.next_run
        end,
        first_after = case
          when job_schedules.schedule = excluded.schedule and job_schedules.timezone = excluded.timezone
            then job_schedules.first_after
          else excluded.first_after
        end,
        tenant = excluded.tenant,
        locked_until = null;
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
  select s.job_name, s.schedule, s.timezone, s.queue, s.tenant, s.next_run, s.last_run, s.locked_until, s.created_at
  from better_supabase.job_schedules s
  where (list_schedules.name_prefix is null or starts_with(s.job_name, list_schedules.name_prefix))
    and (list_schedules.for_tenant is null or s.tenant = list_schedules.for_tenant)
  order by s.job_name;
$$;

-- Removes every schedule of a tenant, for tenant deletion. Returns how many.
create or replace function better_supabase.unschedule_tenant(tenant text)
returns integer
language sql
security definer
set search_path = ''
as $$
  with removed as (
    delete from better_supabase.job_schedules s where s.tenant = unschedule_tenant.tenant returning 1
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
    delete from better_supabase.job_schedules s where s.job_name = unschedule_job.job_name returning 1
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
      select s.job_name
      from better_supabase.job_schedules s
      where (s.next_run is null or s.next_run <= clock_timestamp())
        and (s.locked_until is null or s.locked_until < clock_timestamp())
      order by s.next_run nulls first
      limit greatest(batch, 1)
      for update skip locked
    )
    update better_supabase.job_schedules s
    set locked_until = clock_timestamp() + make_interval(secs => lease)
    from due
    where s.job_name = due.job_name
    returning s.job_name, s.schedule, s.timezone, s.queue, s.payload, s.next_run, s.first_after;
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
    update better_supabase.job_schedules s
    set next_run = date_trunc('milliseconds', advance_schedule.next_run),
        last_run = coalesce(ran, s.last_run),
        first_after = null,
        locked_until = null
    where s.job_name = advance_schedule.job_name
      and (
        date_trunc('milliseconds', s.next_run) = date_trunc('milliseconds', ran)
        or (s.next_run is null and s.first_after is not null)
      )
    returning 1
  )
  select exists (select 1 from advanced);
$$;`;

const GRANTS = (backend: JobsBackend): string =>
  serviceOnly([
    ...(backend === "pgmq"
      ? ["index_job_queue(text)", "ensure_job_queue(text)"]
      : []),
    "enqueue_job(text, jsonb, integer, integer, text, boolean)",
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

function jobsSql(ctx: ModuleContext): string {
  const backend = jobsBackend(ctx);
  const scheduler = jobsScheduler(ctx);
  return [
    SCHEMA,
    LEGACY,
    backend === "pgmq" ? PGMQ : TABLE,
    scheduler === "pg_cron" ? PG_CRON(backend) : DRAIN,
    GRANTS(backend),
  ].join("\n\n");
}

export const JOBS: ModuleDefinition = {
  name: "jobs",
  title: "Job queue",
  description:
    "Typed jobs on Supabase Queues (pgmq) or a plain table (modules.jobs.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.",
  requires: [],
  target: "schema",
  version: 6,
  names: { tables: {}, options: ["backend", "scheduler"] },
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
  ],
  build: jobsSql,
};
