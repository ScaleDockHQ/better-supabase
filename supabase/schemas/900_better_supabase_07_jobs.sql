-- better-supabase module: jobs (0.5.1)
-- @bs-module jobs@6 managed
-- Typed jobs on Supabase Queues (pgmq) or a plain table (modules.jobs.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).
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
drop function if exists better_supabase.claim_due_schedules(integer, integer);

-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
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
$$;

-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
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
declare
  -- pg_cron is optional: its functions are looked up, not named, so
  -- plpgsql_check (supabase db lint) passes without the extension.
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
  v_id bigint;
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set sql.modules.jobs.options.scheduler to "drain" to keep one per schedule';
  end if;
  if v_schedule is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set sql.modules.jobs.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set sql.modules.jobs.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;
  perform better_supabase.ensure_job_queue(queue);
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
$$;

revoke execute on function better_supabase.index_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.index_job_queue(text) to service_role;
revoke execute on function better_supabase.ensure_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.ensure_job_queue(text) to service_role;
revoke execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) to service_role;
revoke execute on function better_supabase.claim_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_jobs(text, integer, integer) to service_role;
revoke execute on function better_supabase.complete_job(text, bigint, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_job(text, bigint, integer) to service_role;
revoke execute on function better_supabase.fail_job(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_job(text, bigint, integer, text, integer) to service_role;
revoke execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) to service_role;
revoke execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text) to service_role;
revoke execute on function better_supabase.unschedule_job(text) from public, anon, authenticated;
grant execute on function better_supabase.unschedule_job(text) to service_role;
revoke execute on function better_supabase.list_schedules(text, text) from public, anon, authenticated;
grant execute on function better_supabase.list_schedules(text, text) to service_role;
revoke execute on function better_supabase.unschedule_tenant(text) from public, anon, authenticated;
grant execute on function better_supabase.unschedule_tenant(text) to service_role;
revoke execute on function better_supabase.claim_due_schedules(integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_due_schedules(integer, integer) to service_role;
revoke execute on function better_supabase.advance_schedule(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.advance_schedule(text, timestamptz, timestamptz) to service_role;
revoke execute on function better_supabase.purge_job_archive(text, interval, integer, interval) from public, anon, authenticated;
grant execute on function better_supabase.purge_job_archive(text, interval, integer, interval) to service_role;
revoke execute on function better_supabase.replay_dead_job(text, bigint) from public, anon, authenticated;
grant execute on function better_supabase.replay_dead_job(text, bigint) to service_role;
revoke execute on function better_supabase.job_queue_stats(text) from public, anon, authenticated;
grant execute on function better_supabase.job_queue_stats(text) to service_role;
revoke execute on function better_supabase.list_dead_jobs(text, integer, bigint) from public, anon, authenticated;
grant execute on function better_supabase.list_dead_jobs(text, integer, bigint) to service_role;
revoke execute on function better_supabase.retry_dead_jobs(text, bigint[], integer) from public, anon, authenticated;
grant execute on function better_supabase.retry_dead_jobs(text, bigint[], integer) to service_role;

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
