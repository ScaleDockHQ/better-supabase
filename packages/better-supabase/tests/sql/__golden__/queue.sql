-- ==== alone: schema supabase/schemas/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block queue@14 managed
-- @bsb-hash sha256:c139c6be1f5031c83e1fe6bbc28f7abfd8219c71f74b151ee64498fa806ddb1f
-- Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).

-- enqueue_job before dedupe_running.

-- schedule_job before time zones.

-- purge_job_archive before dead letters had their own retention.

-- schedule_job before schedules had a tenant.

-- claim_due_schedules returns first_after now; create or replace can't change a return type.


-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Wakes listenForWork (better-supabase/postgres) on channel better_supabase_work.
create or replace function better_supabase.job_queue_notify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', pg_catalog.json_build_object('kind', 'queue', 'queue', tg_argv[0])::text);
  end if;
  return null;
end;
$$;
revoke all on function better_supabase.job_queue_notify() from public;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table and its archive (enqueue_job_once) get a partial index on it.
-- Each queue table also gets the statement trigger that notifies
-- better_supabase_work.
create or replace function better_supabase.index_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'create or replace trigger bsb_notify_work after insert on pgmq.%I referencing new table as new_rows for each statement execute function better_supabase.job_queue_notify(%L)',
    'q_' || queue,
    queue
  );
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
-- returns its id, and a waiting message moves to the earlier of its time and
-- the new delay. With dedupe_running false only a message no worker has
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
      -- A message nobody has read yet moves earlier when this enqueue is due
      -- sooner, never later.
      execute format('update pgmq.%I set vt = least(vt, clock_timestamp() + make_interval(secs => $2)) where msg_id = $1 and read_ct = 0', 'q_' || queue)
        using existing, greatest(delay, 0);
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

-- The queues among queues that have a message claim_jobs takes now, so a
-- drain skips the empty ones in one round trip. A queue without its pgmq
-- table has none.
create or replace function better_supabase.ready_job_queues(queues text[])
returns table (queue text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_ready boolean;
begin
  foreach v_name in array coalesce(queues, '{}') loop
    if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || v_name)) is not null then
      execute format('select exists (select 1 from pgmq.%I where vt <= clock_timestamp())', 'q_' || v_name)
        into v_ready;
      if v_ready then
        queue := v_name;
        return next;
      end if;
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
  null;
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

create or replace function better_supabase.schedule_has_work(probe text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_probe regprocedure := pg_catalog.to_regprocedure(probe || '()');
  v_work boolean;
begin
  if v_probe is null then
    return true;
  end if;
  execute format('select %s()', v_probe::oid::regproc) into v_work;
  return coalesce(v_work, true);
exception when others then
  return true;
end;
$$;

-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
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
  tenant text default null,
  probe text default null
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
  end if;
  perform better_supabase.ensure_job_queue(queue);
  if probe is not null and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(probe || '()') and p.prorettype = 'boolean'::regtype
  ) then
    raise exception 'The probe % is not a function without arguments that returns boolean', probe using errcode = '22023';
  end if;
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text)
      || case when probe is null then '' else format(' where better_supabase.schedule_has_work(%L)', probe) end;
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
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean;
  v_removed boolean;
begin
  if v_unschedule is null or v_jobs is null then
    return false;
  end if;
  -- cron.unschedule raises for a name it doesn't know.
  execute format('select exists (select 1 from %s j where j.jobname = $1)', v_jobs)
    into v_found
    using job_name;
  if not v_found then
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
-- payload, tenant or next run, so those are null.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, lock_expires_at timestamptz, created_at timestamptz, payload jsonb, probe text)
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
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb, null::text
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

-- Supabase Cron as the clock: with blocks.queue.options.httpTick, pg_cron calls
-- this every minute (job bsb_jobs_tick). It posts to the URL in the Vault secret
-- jobs_tick_url (the drain route on pgmq, jobs.schedulesRoute on Vercel Queues)
-- with the bearer token in jobs_tick_token, usually CRON_SECRET. Returns the
-- pg_net request id, or null with a warning while a secret is missing.
create or replace function better_supabase.http_tick()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- pg_net and Vault are looked up, not named, so plpgsql_check (supabase db
  -- lint) passes without them.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
  v_url text;
  v_token text;
  v_id bigint;
begin
  if v_post is null then
    raise exception 'the queue tick needs pg_net: create extension pg_net'
      using hint = 'QUEUE_TICK_NO_PG_NET';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'the queue tick reads its URL and token from Vault: create extension supabase_vault'
      using hint = 'QUEUE_TICK_NO_VAULT';
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'jobs_tick_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_token using 'jobs_tick_token';
  if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
    raise warning 'http_tick skipped: set the Vault secrets jobs_tick_url and jobs_tick_token';
    return null;
  end if;
  execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
    into v_id
    using v_url, '{}'::jsonb, jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_token
    ), 55000;
  return v_id;
end;
$$;

-- Leases: claim_lease answers claimed (the caller holds it until expires_at),
-- busy (another holder does; retry_after_ms says when it ends) or completed
-- (a holder finished it, and it stays finished until its keep time ends).
create table "better_supabase"."job_leases" (
  "scope" text not null default '',
  "key" text not null,
  "holder" uuid not null,
  "state" text not null default 'held' constraint bsb_job_leases_state_check check ("state" in ('held', 'completed')),
  "expires_at" timestamptz not null,
  primary key ("scope", "key")
);
alter table "better_supabase"."job_leases" enable row level security;
revoke all on "better_supabase"."job_leases" from public, anon, authenticated;
grant all on "better_supabase"."job_leases" to service_role;

create or replace function better_supabase.claim_lease(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken "better_supabase"."job_leases"%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into "better_supabase"."job_leases" as l ("scope", "key", "holder", "state", "expires_at")
  values (scope, key, token, 'held', lease_expires_at)
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "state" = 'held', "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from "better_supabase"."job_leases" l
  where l."scope" = claim_lease.scope and l."key" = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken."state" = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken."expires_at",
    greatest(ceil(extract(epoch from taken."expires_at" - now()) * 1000)::integer, 0);
end;
$$;

-- Moves the expiry of a held lease the holder still has; false once it ran out
-- or another holder took it over.
create or replace function better_supabase.extend_lease_claim(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update "better_supabase"."job_leases" l
    set "expires_at" = now() + make_interval(secs => greatest(coalesce(extend_lease_claim.lease_seconds, 60), 1))
    where l."scope" = extend_lease_claim.scope and l."key" = extend_lease_claim.key
      and l."holder" = extend_lease_claim.holder and l."state" = 'held'
      and l."expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- Marks the work done: later claims answer completed for keep_seconds (a day by
-- default), then the key can be claimed again. False when another holder took
-- the lease over.
create or replace function better_supabase.complete_lease(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update "better_supabase"."job_leases" l
    set "state" = 'completed',
        "expires_at" = now() + make_interval(secs => greatest(coalesce(complete_lease.keep_seconds, 86400), 1))
    where l."scope" = complete_lease.scope and l."key" = complete_lease.key
      and l."holder" = complete_lease.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from done)
$$;

-- On failure: gives the lease up so the next claim succeeds at once. False when
-- another holder has it now, or it was completed.
create or replace function better_supabase.release_lease_claim(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from "better_supabase"."job_leases" l
    where l."scope" = release_lease_claim.scope and l."key" = release_lease_claim.key
      and l."holder" = release_lease_claim.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from released)
$$;

revoke execute on function better_supabase.index_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.index_job_queue(text) to service_role;
revoke execute on function better_supabase.ensure_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.ensure_job_queue(text) to service_role;
revoke execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) to service_role;
revoke execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) to service_role;
revoke execute on function better_supabase.claim_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_jobs(text, integer, integer) to service_role;
revoke execute on function better_supabase.ready_job_queues(text[]) from public, anon, authenticated;
grant execute on function better_supabase.ready_job_queues(text[]) to service_role;
revoke execute on function better_supabase.complete_job(text, bigint, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_job(text, bigint, integer) to service_role;
revoke execute on function better_supabase.fail_job(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_job(text, bigint, integer, text, integer) to service_role;
revoke execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) to service_role;
revoke execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) to service_role;
revoke execute on function better_supabase.schedule_has_work(text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_has_work(text) to service_role;
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
revoke execute on function better_supabase.http_tick() from public, anon, authenticated;
grant execute on function better_supabase.http_tick() to service_role;
revoke execute on function better_supabase.claim_lease(text, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_lease(text, text, integer) to service_role;
revoke execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.complete_lease(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_lease(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.release_lease_claim(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_lease_claim(text, text, uuid) to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block-data queue
-- @bsb-hash sha256:fa8ce95b3ded0ed37ebd683153a0c9146ca7c434b373a882f59229e979c21151
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 14, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block queue@14 managed
-- @bsb-hash sha256:66e3e62d25cef66bfef8a7078abf047b91aa22ef68c708947429a4fd20a02662
-- Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).

-- enqueue_job before dedupe_running.

-- schedule_job before time zones.

-- purge_job_archive before dead letters had their own retention.

-- schedule_job before schedules had a tenant.

-- claim_due_schedules returns first_after now; create or replace can't change a return type.


-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Wakes listenForWork (better-supabase/postgres) on channel better_supabase_work.
create or replace function better_supabase.job_queue_notify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', pg_catalog.json_build_object('kind', 'queue', 'queue', tg_argv[0])::text);
  end if;
  return null;
end;
$$;
revoke all on function better_supabase.job_queue_notify() from public;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table and its archive (enqueue_job_once) get a partial index on it.
-- Each queue table also gets the statement trigger that notifies
-- better_supabase_work.
create or replace function better_supabase.index_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'create or replace trigger bsb_notify_work after insert on pgmq.%I referencing new table as new_rows for each statement execute function better_supabase.job_queue_notify(%L)',
    'q_' || queue,
    queue
  );
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
-- returns its id, and a waiting message moves to the earlier of its time and
-- the new delay. With dedupe_running false only a message no worker has
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
      -- A message nobody has read yet moves earlier when this enqueue is due
      -- sooner, never later.
      execute format('update pgmq.%I set vt = least(vt, clock_timestamp() + make_interval(secs => $2)) where msg_id = $1 and read_ct = 0', 'q_' || queue)
        using existing, greatest(delay, 0);
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

-- The queues among queues that have a message claim_jobs takes now, so a
-- drain skips the empty ones in one round trip. A queue without its pgmq
-- table has none.
create or replace function better_supabase.ready_job_queues(queues text[])
returns table (queue text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_ready boolean;
begin
  foreach v_name in array coalesce(queues, '{}') loop
    if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || v_name)) is not null then
      execute format('select exists (select 1 from pgmq.%I where vt <= clock_timestamp())', 'q_' || v_name)
        into v_ready;
      if v_ready then
        queue := v_name;
        return next;
      end if;
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
  if "better_supabase"."is_held_memo"('job_archive', (null)::text) then
    return 0;
  end if;
  older_than := coalesce("better_supabase"."retention_for_memo"('job_archive', (null)::text), older_than);
  dead_older_than := coalesce("better_supabase"."retention_for_memo"('job_archive', (null)::text), dead_older_than);
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

create or replace function better_supabase.schedule_has_work(probe text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_probe regprocedure := pg_catalog.to_regprocedure(probe || '()');
  v_work boolean;
begin
  if v_probe is null then
    return true;
  end if;
  execute format('select %s()', v_probe::oid::regproc) into v_work;
  return coalesce(v_work, true);
exception when others then
  return true;
end;
$$;

-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
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
  tenant text default null,
  probe text default null
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
  end if;
  perform better_supabase.ensure_job_queue(queue);
  if probe is not null and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(probe || '()') and p.prorettype = 'boolean'::regtype
  ) then
    raise exception 'The probe % is not a function without arguments that returns boolean', probe using errcode = '22023';
  end if;
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text)
      || case when probe is null then '' else format(' where better_supabase.schedule_has_work(%L)', probe) end;
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
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean;
  v_removed boolean;
begin
  if v_unschedule is null or v_jobs is null then
    return false;
  end if;
  -- cron.unschedule raises for a name it doesn't know.
  execute format('select exists (select 1 from %s j where j.jobname = $1)', v_jobs)
    into v_found
    using job_name;
  if not v_found then
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
-- payload, tenant or next run, so those are null.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, lock_expires_at timestamptz, created_at timestamptz, payload jsonb, probe text)
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
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb, null::text
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

-- Supabase Cron as the clock: with blocks.queue.options.httpTick, pg_cron calls
-- this every minute (job bsb_jobs_tick). It posts to the URL in the Vault secret
-- jobs_tick_url (the drain route on pgmq, jobs.schedulesRoute on Vercel Queues)
-- with the bearer token in jobs_tick_token, usually CRON_SECRET. Returns the
-- pg_net request id, or null with a warning while a secret is missing.
create or replace function better_supabase.http_tick()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- pg_net and Vault are looked up, not named, so plpgsql_check (supabase db
  -- lint) passes without them.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
  v_url text;
  v_token text;
  v_id bigint;
begin
  if v_post is null then
    raise exception 'the queue tick needs pg_net: create extension pg_net'
      using hint = 'QUEUE_TICK_NO_PG_NET';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'the queue tick reads its URL and token from Vault: create extension supabase_vault'
      using hint = 'QUEUE_TICK_NO_VAULT';
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'jobs_tick_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_token using 'jobs_tick_token';
  if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
    raise warning 'http_tick skipped: set the Vault secrets jobs_tick_url and jobs_tick_token';
    return null;
  end if;
  execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
    into v_id
    using v_url, '{}'::jsonb, jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_token
    ), 55000;
  return v_id;
end;
$$;

-- Leases: claim_lease answers claimed (the caller holds it until expires_at),
-- busy (another holder does; retry_after_ms says when it ends) or completed
-- (a holder finished it, and it stays finished until its keep time ends).
create table "better_supabase"."job_leases" (
  "scope" text not null default '',
  "key" text not null,
  "holder" uuid not null,
  "state" text not null default 'held' constraint bsb_job_leases_state_check check ("state" in ('held', 'completed')),
  "expires_at" timestamptz not null,
  primary key ("scope", "key")
);
alter table "better_supabase"."job_leases" enable row level security;
revoke all on "better_supabase"."job_leases" from public, anon, authenticated;
grant all on "better_supabase"."job_leases" to service_role;

create or replace function better_supabase.claim_lease(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken "better_supabase"."job_leases"%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into "better_supabase"."job_leases" as l ("scope", "key", "holder", "state", "expires_at")
  values (scope, key, token, 'held', lease_expires_at)
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "state" = 'held', "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from "better_supabase"."job_leases" l
  where l."scope" = claim_lease.scope and l."key" = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken."state" = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken."expires_at",
    greatest(ceil(extract(epoch from taken."expires_at" - now()) * 1000)::integer, 0);
end;
$$;

-- Moves the expiry of a held lease the holder still has; false once it ran out
-- or another holder took it over.
create or replace function better_supabase.extend_lease_claim(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update "better_supabase"."job_leases" l
    set "expires_at" = now() + make_interval(secs => greatest(coalesce(extend_lease_claim.lease_seconds, 60), 1))
    where l."scope" = extend_lease_claim.scope and l."key" = extend_lease_claim.key
      and l."holder" = extend_lease_claim.holder and l."state" = 'held'
      and l."expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- Marks the work done: later claims answer completed for keep_seconds (a day by
-- default), then the key can be claimed again. False when another holder took
-- the lease over.
create or replace function better_supabase.complete_lease(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update "better_supabase"."job_leases" l
    set "state" = 'completed',
        "expires_at" = now() + make_interval(secs => greatest(coalesce(complete_lease.keep_seconds, 86400), 1))
    where l."scope" = complete_lease.scope and l."key" = complete_lease.key
      and l."holder" = complete_lease.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from done)
$$;

-- On failure: gives the lease up so the next claim succeeds at once. False when
-- another holder has it now, or it was completed.
create or replace function better_supabase.release_lease_claim(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from "better_supabase"."job_leases" l
    where l."scope" = release_lease_claim.scope and l."key" = release_lease_claim.key
      and l."holder" = release_lease_claim.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from released)
$$;

revoke execute on function better_supabase.index_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.index_job_queue(text) to service_role;
revoke execute on function better_supabase.ensure_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.ensure_job_queue(text) to service_role;
revoke execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) to service_role;
revoke execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) to service_role;
revoke execute on function better_supabase.claim_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_jobs(text, integer, integer) to service_role;
revoke execute on function better_supabase.ready_job_queues(text[]) from public, anon, authenticated;
grant execute on function better_supabase.ready_job_queues(text[]) to service_role;
revoke execute on function better_supabase.complete_job(text, bigint, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_job(text, bigint, integer) to service_role;
revoke execute on function better_supabase.fail_job(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_job(text, bigint, integer, text, integer) to service_role;
revoke execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) to service_role;
revoke execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) to service_role;
revoke execute on function better_supabase.schedule_has_work(text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_has_work(text) to service_role;
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
revoke execute on function better_supabase.http_tick() from public, anon, authenticated;
grant execute on function better_supabase.http_tick() to service_role;
revoke execute on function better_supabase.claim_lease(text, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_lease(text, text, integer) to service_role;
revoke execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.complete_lease(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_lease(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.release_lease_claim(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_lease_claim(text, text, uuid) to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block-data queue
-- @bsb-hash sha256:fa8ce95b3ded0ed37ebd683153a0c9146ca7c434b373a882f59229e979c21151
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 14, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: throws
-- blocks.queue.schema: the queue block always installs in better_supabase. Remove schema.

-- ==== api schema: schema supabase/schemas/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block queue@14 managed
-- @bsb-hash sha256:b30e8e2bf3aaab2110042a31942086ac089f7ab1d3e81ac5a2d8ff897cadd365
-- Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).

-- enqueue_job before dedupe_running.

-- schedule_job before time zones.

-- purge_job_archive before dead letters had their own retention.

-- schedule_job before schedules had a tenant.

-- claim_due_schedules returns first_after now; create or replace can't change a return type.


-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Wakes listenForWork (better-supabase/postgres) on channel better_supabase_work.
create or replace function better_supabase.job_queue_notify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', pg_catalog.json_build_object('kind', 'queue', 'queue', tg_argv[0])::text);
  end if;
  return null;
end;
$$;
revoke all on function better_supabase.job_queue_notify() from public;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table and its archive (enqueue_job_once) get a partial index on it.
-- Each queue table also gets the statement trigger that notifies
-- better_supabase_work.
create or replace function better_supabase.index_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'create or replace trigger bsb_notify_work after insert on pgmq.%I referencing new table as new_rows for each statement execute function better_supabase.job_queue_notify(%L)',
    'q_' || queue,
    queue
  );
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
-- returns its id, and a waiting message moves to the earlier of its time and
-- the new delay. With dedupe_running false only a message no worker has
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
      -- A message nobody has read yet moves earlier when this enqueue is due
      -- sooner, never later.
      execute format('update pgmq.%I set vt = least(vt, clock_timestamp() + make_interval(secs => $2)) where msg_id = $1 and read_ct = 0', 'q_' || queue)
        using existing, greatest(delay, 0);
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

-- The queues among queues that have a message claim_jobs takes now, so a
-- drain skips the empty ones in one round trip. A queue without its pgmq
-- table has none.
create or replace function better_supabase.ready_job_queues(queues text[])
returns table (queue text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_ready boolean;
begin
  foreach v_name in array coalesce(queues, '{}') loop
    if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || v_name)) is not null then
      execute format('select exists (select 1 from pgmq.%I where vt <= clock_timestamp())', 'q_' || v_name)
        into v_ready;
      if v_ready then
        queue := v_name;
        return next;
      end if;
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
  null;
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

create or replace function better_supabase.schedule_has_work(probe text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_probe regprocedure := pg_catalog.to_regprocedure(probe || '()');
  v_work boolean;
begin
  if v_probe is null then
    return true;
  end if;
  execute format('select %s()', v_probe::oid::regproc) into v_work;
  return coalesce(v_work, true);
exception when others then
  return true;
end;
$$;

-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
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
  tenant text default null,
  probe text default null
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
  end if;
  perform better_supabase.ensure_job_queue(queue);
  if probe is not null and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(probe || '()') and p.prorettype = 'boolean'::regtype
  ) then
    raise exception 'The probe % is not a function without arguments that returns boolean', probe using errcode = '22023';
  end if;
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text)
      || case when probe is null then '' else format(' where better_supabase.schedule_has_work(%L)', probe) end;
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
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean;
  v_removed boolean;
begin
  if v_unschedule is null or v_jobs is null then
    return false;
  end if;
  -- cron.unschedule raises for a name it doesn't know.
  execute format('select exists (select 1 from %s j where j.jobname = $1)', v_jobs)
    into v_found
    using job_name;
  if not v_found then
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
-- payload, tenant or next run, so those are null.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, lock_expires_at timestamptz, created_at timestamptz, payload jsonb, probe text)
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
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb, null::text
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

-- Supabase Cron as the clock: with blocks.queue.options.httpTick, pg_cron calls
-- this every minute (job bsb_jobs_tick). It posts to the URL in the Vault secret
-- jobs_tick_url (the drain route on pgmq, jobs.schedulesRoute on Vercel Queues)
-- with the bearer token in jobs_tick_token, usually CRON_SECRET. Returns the
-- pg_net request id, or null with a warning while a secret is missing.
create or replace function better_supabase.http_tick()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- pg_net and Vault are looked up, not named, so plpgsql_check (supabase db
  -- lint) passes without them.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
  v_url text;
  v_token text;
  v_id bigint;
begin
  if v_post is null then
    raise exception 'the queue tick needs pg_net: create extension pg_net'
      using hint = 'QUEUE_TICK_NO_PG_NET';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'the queue tick reads its URL and token from Vault: create extension supabase_vault'
      using hint = 'QUEUE_TICK_NO_VAULT';
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'jobs_tick_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_token using 'jobs_tick_token';
  if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
    raise warning 'http_tick skipped: set the Vault secrets jobs_tick_url and jobs_tick_token';
    return null;
  end if;
  execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
    into v_id
    using v_url, '{}'::jsonb, jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_token
    ), 55000;
  return v_id;
end;
$$;

-- Leases: claim_lease answers claimed (the caller holds it until expires_at),
-- busy (another holder does; retry_after_ms says when it ends) or completed
-- (a holder finished it, and it stays finished until its keep time ends).
create table "better_supabase"."job_leases" (
  "scope" text not null default '',
  "key" text not null,
  "holder" uuid not null,
  "state" text not null default 'held' constraint bsb_job_leases_state_check check ("state" in ('held', 'completed')),
  "expires_at" timestamptz not null,
  primary key ("scope", "key")
);
alter table "better_supabase"."job_leases" enable row level security;
revoke all on "better_supabase"."job_leases" from public, anon, authenticated;
grant all on "better_supabase"."job_leases" to service_role;

create or replace function better_supabase.claim_lease(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken "better_supabase"."job_leases"%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into "better_supabase"."job_leases" as l ("scope", "key", "holder", "state", "expires_at")
  values (scope, key, token, 'held', lease_expires_at)
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "state" = 'held', "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from "better_supabase"."job_leases" l
  where l."scope" = claim_lease.scope and l."key" = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken."state" = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken."expires_at",
    greatest(ceil(extract(epoch from taken."expires_at" - now()) * 1000)::integer, 0);
end;
$$;

-- Moves the expiry of a held lease the holder still has; false once it ran out
-- or another holder took it over.
create or replace function better_supabase.extend_lease_claim(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update "better_supabase"."job_leases" l
    set "expires_at" = now() + make_interval(secs => greatest(coalesce(extend_lease_claim.lease_seconds, 60), 1))
    where l."scope" = extend_lease_claim.scope and l."key" = extend_lease_claim.key
      and l."holder" = extend_lease_claim.holder and l."state" = 'held'
      and l."expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- Marks the work done: later claims answer completed for keep_seconds (a day by
-- default), then the key can be claimed again. False when another holder took
-- the lease over.
create or replace function better_supabase.complete_lease(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update "better_supabase"."job_leases" l
    set "state" = 'completed',
        "expires_at" = now() + make_interval(secs => greatest(coalesce(complete_lease.keep_seconds, 86400), 1))
    where l."scope" = complete_lease.scope and l."key" = complete_lease.key
      and l."holder" = complete_lease.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from done)
$$;

-- On failure: gives the lease up so the next claim succeeds at once. False when
-- another holder has it now, or it was completed.
create or replace function better_supabase.release_lease_claim(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from "better_supabase"."job_leases" l
    where l."scope" = release_lease_claim.scope and l."key" = release_lease_claim.key
      and l."holder" = release_lease_claim.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from released)
$$;

revoke execute on function better_supabase.index_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.index_job_queue(text) to service_role;
revoke execute on function better_supabase.ensure_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.ensure_job_queue(text) to service_role;
revoke execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) to service_role;
revoke execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) to service_role;
revoke execute on function better_supabase.claim_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_jobs(text, integer, integer) to service_role;
revoke execute on function better_supabase.ready_job_queues(text[]) from public, anon, authenticated;
grant execute on function better_supabase.ready_job_queues(text[]) to service_role;
revoke execute on function better_supabase.complete_job(text, bigint, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_job(text, bigint, integer) to service_role;
revoke execute on function better_supabase.fail_job(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_job(text, bigint, integer, text, integer) to service_role;
revoke execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) to service_role;
revoke execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) to service_role;
revoke execute on function better_supabase.schedule_has_work(text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_has_work(text) to service_role;
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
revoke execute on function better_supabase.http_tick() from public, anon, authenticated;
grant execute on function better_supabase.http_tick() to service_role;
revoke execute on function better_supabase.claim_lease(text, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_lease(text, text, integer) to service_role;
revoke execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.complete_lease(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_lease(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.release_lease_claim(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_lease_claim(text, text, uuid) to service_role;

-- blocks.queue.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."index_job_queue"(queue text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."index_job_queue"($1) $$;
revoke execute on function "api"."index_job_queue"(text) from public, anon, authenticated;
grant execute on function "api"."index_job_queue"(text) to service_role;

create or replace function "api"."ensure_job_queue"(queue text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ensure_job_queue"($1) $$;
revoke execute on function "api"."ensure_job_queue"(text) from public, anon, authenticated;
grant execute on function "api"."ensure_job_queue"(text) to service_role;

create or replace function "api"."enqueue_job"(queue text, payload jsonb default '{}', delay integer default 0, max_attempts integer default 5, dedupe_key text default null, dedupe_running boolean default true)
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enqueue_job"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."enqueue_job"(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function "api"."enqueue_job"(text, jsonb, integer, integer, text, boolean) to service_role;

create or replace function "api"."enqueue_job_once"(queue text, payload jsonb, dedupe_key text, delay integer default 0, max_attempts integer default 5)
returns table (id bigint, duplicate boolean)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."enqueue_job_once"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."enqueue_job_once"(text, jsonb, text, integer, integer) from public, anon, authenticated;
grant execute on function "api"."enqueue_job_once"(text, jsonb, text, integer, integer) to service_role;

create or replace function "api"."claim_jobs"(queue text, lease integer default 300, batch integer default 1)
returns table (id bigint, attempts integer, enqueued_at timestamptz, visible_until timestamptz, message jsonb)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."claim_jobs"($1, $2, $3) $$;
revoke execute on function "api"."claim_jobs"(text, integer, integer) from public, anon, authenticated;
grant execute on function "api"."claim_jobs"(text, integer, integer) to service_role;

create or replace function "api"."ready_job_queues"(queues text[])
returns table (queue text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."ready_job_queues"($1) $$;
revoke execute on function "api"."ready_job_queues"(text[]) from public, anon, authenticated;
grant execute on function "api"."ready_job_queues"(text[]) to service_role;

create or replace function "api"."complete_job"(queue text, job_id bigint, attempt integer)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_job"($1, $2, $3) $$;
revoke execute on function "api"."complete_job"(text, bigint, integer) from public, anon, authenticated;
grant execute on function "api"."complete_job"(text, bigint, integer) to service_role;

create or replace function "api"."fail_job"(queue text, job_id bigint, attempt integer, error text, retry_in integer default null)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."fail_job"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."fail_job"(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function "api"."fail_job"(text, bigint, integer, text, integer) to service_role;

create or replace function "api"."extend_job_lease"(queue text, job_id bigint, attempt integer, lease integer)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."extend_job_lease"($1, $2, $3, $4) $$;
revoke execute on function "api"."extend_job_lease"(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function "api"."extend_job_lease"(text, bigint, integer, integer) to service_role;

create or replace function "api"."schedule_job"(job_name text, schedule text, queue text, payload jsonb default '{}', timezone text default 'UTC', next_run timestamptz default null, tenant text default null, probe text default null)
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_job"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."schedule_job"(text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function "api"."schedule_job"(text, text, text, jsonb, text, timestamptz, text, text) to service_role;

create or replace function "api"."schedule_has_work"(probe text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_has_work"($1) $$;
revoke execute on function "api"."schedule_has_work"(text) from public, anon, authenticated;
grant execute on function "api"."schedule_has_work"(text) to service_role;

create or replace function "api"."unschedule_job"(job_name text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unschedule_job"($1) $$;
revoke execute on function "api"."unschedule_job"(text) from public, anon, authenticated;
grant execute on function "api"."unschedule_job"(text) to service_role;

create or replace function "api"."list_schedules"(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, lock_expires_at timestamptz, created_at timestamptz, payload jsonb, probe text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_schedules"($1, $2) $$;
revoke execute on function "api"."list_schedules"(text, text) from public, anon, authenticated;
grant execute on function "api"."list_schedules"(text, text) to service_role;

create or replace function "api"."unschedule_tenant"(tenant text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unschedule_tenant"($1) $$;
revoke execute on function "api"."unschedule_tenant"(text) from public, anon, authenticated;
grant execute on function "api"."unschedule_tenant"(text) to service_role;

create or replace function "api"."claim_due_schedules"(lease integer default 60, batch integer default 100)
returns table (job_name text, schedule text, timezone text, queue text, payload jsonb, next_run timestamptz, first_after timestamptz)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."claim_due_schedules"($1, $2) $$;
revoke execute on function "api"."claim_due_schedules"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."claim_due_schedules"(integer, integer) to service_role;

create or replace function "api"."advance_schedule"(job_name text, ran timestamptz, next_run timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."advance_schedule"($1, $2, $3) $$;
revoke execute on function "api"."advance_schedule"(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "api"."advance_schedule"(text, timestamptz, timestamptz) to service_role;

create or replace function "api"."purge_job_archive"(queue text, older_than interval default '7 days', batch integer default 10000, dead_older_than interval default '30 days')
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_job_archive"($1, $2, $3, $4) $$;
revoke execute on function "api"."purge_job_archive"(text, interval, integer, interval) from public, anon, authenticated;
grant execute on function "api"."purge_job_archive"(text, interval, integer, interval) to service_role;

create or replace function "api"."replay_dead_job"(queue text, job_id bigint)
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."replay_dead_job"($1, $2) $$;
revoke execute on function "api"."replay_dead_job"(text, bigint) from public, anon, authenticated;
grant execute on function "api"."replay_dead_job"(text, bigint) to service_role;

create or replace function "api"."job_queue_stats"(queue text)
returns table (ready bigint, in_flight bigint, delayed bigint, dead bigint, oldest_age_seconds double precision)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."job_queue_stats"($1) $$;
revoke execute on function "api"."job_queue_stats"(text) from public, anon, authenticated;
grant execute on function "api"."job_queue_stats"(text) to service_role;

create or replace function "api"."list_dead_jobs"(queue text, max_rows integer default 100, before_id bigint default null)
returns table (id bigint, attempts integer, enqueued_at timestamptz, died_at timestamptz, message jsonb)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_dead_jobs"($1, $2, $3) $$;
revoke execute on function "api"."list_dead_jobs"(text, integer, bigint) from public, anon, authenticated;
grant execute on function "api"."list_dead_jobs"(text, integer, bigint) to service_role;

create or replace function "api"."retry_dead_jobs"(queue text, ids bigint[] default null, batch integer default 1000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."retry_dead_jobs"($1, $2, $3) $$;
revoke execute on function "api"."retry_dead_jobs"(text, bigint[], integer) from public, anon, authenticated;
grant execute on function "api"."retry_dead_jobs"(text, bigint[], integer) to service_role;

create or replace function "api"."http_tick"()
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."http_tick"() $$;
revoke execute on function "api"."http_tick"() from public, anon, authenticated;
grant execute on function "api"."http_tick"() to service_role;

create or replace function "api"."claim_lease"(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."claim_lease"($1, $2, $3) $$;
revoke execute on function "api"."claim_lease"(text, text, integer) from public, anon, authenticated;
grant execute on function "api"."claim_lease"(text, text, integer) to service_role;

create or replace function "api"."extend_lease_claim"(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."extend_lease_claim"($1, $2, $3, $4) $$;
revoke execute on function "api"."extend_lease_claim"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "api"."extend_lease_claim"(text, text, uuid, integer) to service_role;

create or replace function "api"."complete_lease"(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_lease"($1, $2, $3, $4) $$;
revoke execute on function "api"."complete_lease"(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function "api"."complete_lease"(text, text, uuid, integer) to service_role;

create or replace function "api"."release_lease_claim"(scope text, key text, holder uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_lease_claim"($1, $2, $3) $$;
revoke execute on function "api"."release_lease_claim"(text, text, uuid) from public, anon, authenticated;
grant execute on function "api"."release_lease_claim"(text, text, uuid) to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block-data queue
-- @bsb-hash sha256:fa8ce95b3ded0ed37ebd683153a0c9146ca7c434b373a882f59229e979c21151
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 14, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block queue@14 managed
-- @bsb-hash sha256:7ca943cc50b186fc1b093e5c2befacba99ba9be818c204b57a0b4884a3b3191c
-- Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).

-- enqueue_job before dedupe_running.

-- schedule_job before time zones.

-- purge_job_archive before dead letters had their own retention.

-- schedule_job before schedules had a tenant.

-- claim_due_schedules returns first_after now; create or replace can't change a return type.


-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Wakes listenForWork (better-supabase/postgres) on channel better_supabase_work.
create or replace function better_supabase.job_queue_notify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', pg_catalog.json_build_object('kind', 'queue', 'queue', tg_argv[0])::text);
  end if;
  return null;
end;
$$;
revoke all on function better_supabase.job_queue_notify() from public;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table and its archive (enqueue_job_once) get a partial index on it.
-- Each queue table also gets the statement trigger that notifies
-- better_supabase_work.
create or replace function better_supabase.index_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'create or replace trigger bsb_notify_work after insert on pgmq.%I referencing new table as new_rows for each statement execute function better_supabase.job_queue_notify(%L)',
    'q_' || queue,
    queue
  );
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
-- returns its id, and a waiting message moves to the earlier of its time and
-- the new delay. With dedupe_running false only a message no worker has
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
      -- A message nobody has read yet moves earlier when this enqueue is due
      -- sooner, never later.
      execute format('update pgmq.%I set vt = least(vt, clock_timestamp() + make_interval(secs => $2)) where msg_id = $1 and read_ct = 0', 'q_' || queue)
        using existing, greatest(delay, 0);
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

-- The queues among queues that have a message claim_jobs takes now, so a
-- drain skips the empty ones in one round trip. A queue without its pgmq
-- table has none.
create or replace function better_supabase.ready_job_queues(queues text[])
returns table (queue text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_ready boolean;
begin
  foreach v_name in array coalesce(queues, '{}') loop
    if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || v_name)) is not null then
      execute format('select exists (select 1 from pgmq.%I where vt <= clock_timestamp())', 'q_' || v_name)
        into v_ready;
      if v_ready then
        queue := v_name;
        return next;
      end if;
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
  null;
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

create or replace function better_supabase.schedule_has_work(probe text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_probe regprocedure := pg_catalog.to_regprocedure(probe || '()');
  v_work boolean;
begin
  if v_probe is null then
    return true;
  end if;
  execute format('select %s()', v_probe::oid::regproc) into v_work;
  return coalesce(v_work, true);
exception when others then
  return true;
end;
$$;

-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
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
  tenant text default null,
  probe text default null
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
  end if;
  perform better_supabase.ensure_job_queue(queue);
  if probe is not null and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(probe || '()') and p.prorettype = 'boolean'::regtype
  ) then
    raise exception 'The probe % is not a function without arguments that returns boolean', probe using errcode = '22023';
  end if;
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text)
      || case when probe is null then '' else format(' where better_supabase.schedule_has_work(%L)', probe) end;
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
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean;
  v_removed boolean;
begin
  if v_unschedule is null or v_jobs is null then
    return false;
  end if;
  -- cron.unschedule raises for a name it doesn't know.
  execute format('select exists (select 1 from %s j where j.jobname = $1)', v_jobs)
    into v_found
    using job_name;
  if not v_found then
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
-- payload, tenant or next run, so those are null.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, lock_expires_at timestamptz, created_at timestamptz, payload jsonb, probe text)
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
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb, null::text
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

-- Supabase Cron as the clock: with blocks.queue.options.httpTick, pg_cron calls
-- this every minute (job bsb_jobs_tick). It posts to the URL in the Vault secret
-- jobs_tick_url (the drain route on pgmq, jobs.schedulesRoute on Vercel Queues)
-- with the bearer token in jobs_tick_token, usually CRON_SECRET. Returns the
-- pg_net request id, or null with a warning while a secret is missing.
create or replace function better_supabase.http_tick()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- pg_net and Vault are looked up, not named, so plpgsql_check (supabase db
  -- lint) passes without them.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
  v_url text;
  v_token text;
  v_id bigint;
begin
  if v_post is null then
    raise exception 'the queue tick needs pg_net: create extension pg_net'
      using hint = 'QUEUE_TICK_NO_PG_NET';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'the queue tick reads its URL and token from Vault: create extension supabase_vault'
      using hint = 'QUEUE_TICK_NO_VAULT';
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'jobs_tick_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_token using 'jobs_tick_token';
  if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
    raise warning 'http_tick skipped: set the Vault secrets jobs_tick_url and jobs_tick_token';
    return null;
  end if;
  execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
    into v_id
    using v_url, '{}'::jsonb, jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_token
    ), 55000;
  return v_id;
end;
$$;

-- Leases: claim_lease answers claimed (the caller holds it until expires_at),
-- busy (another holder does; retry_after_ms says when it ends) or completed
-- (a holder finished it, and it stays finished until its keep time ends).
-- better_supabase.job_leases is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."job_leases" add column if not exists "scope" text not null default '';
alter table "better_supabase"."job_leases" add column if not exists "key" text;
alter table "better_supabase"."job_leases" add column if not exists "holder" uuid;
alter table "better_supabase"."job_leases" add column if not exists "state" text not null default 'held' constraint bsb_job_leases_state_check check ("state" in ('held', 'completed'));
alter table "better_supabase"."job_leases" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."job_leases" enable row level security;
grant all on "better_supabase"."job_leases" to service_role;
create unique index if not exists "job_leases_scope_key_key" on "better_supabase"."job_leases" ("scope", "key");

create or replace function better_supabase.claim_lease(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken "better_supabase"."job_leases"%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into "better_supabase"."job_leases" as l ("scope", "key", "holder", "state", "expires_at")
  values (scope, key, token, 'held', lease_expires_at)
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "state" = 'held', "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from "better_supabase"."job_leases" l
  where l."scope" = claim_lease.scope and l."key" = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken."state" = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken."expires_at",
    greatest(ceil(extract(epoch from taken."expires_at" - now()) * 1000)::integer, 0);
end;
$$;

-- Moves the expiry of a held lease the holder still has; false once it ran out
-- or another holder took it over.
create or replace function better_supabase.extend_lease_claim(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update "better_supabase"."job_leases" l
    set "expires_at" = now() + make_interval(secs => greatest(coalesce(extend_lease_claim.lease_seconds, 60), 1))
    where l."scope" = extend_lease_claim.scope and l."key" = extend_lease_claim.key
      and l."holder" = extend_lease_claim.holder and l."state" = 'held'
      and l."expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- Marks the work done: later claims answer completed for keep_seconds (a day by
-- default), then the key can be claimed again. False when another holder took
-- the lease over.
create or replace function better_supabase.complete_lease(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update "better_supabase"."job_leases" l
    set "state" = 'completed',
        "expires_at" = now() + make_interval(secs => greatest(coalesce(complete_lease.keep_seconds, 86400), 1))
    where l."scope" = complete_lease.scope and l."key" = complete_lease.key
      and l."holder" = complete_lease.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from done)
$$;

-- On failure: gives the lease up so the next claim succeeds at once. False when
-- another holder has it now, or it was completed.
create or replace function better_supabase.release_lease_claim(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from "better_supabase"."job_leases" l
    where l."scope" = release_lease_claim.scope and l."key" = release_lease_claim.key
      and l."holder" = release_lease_claim.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from released)
$$;

revoke execute on function better_supabase.index_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.index_job_queue(text) to service_role;
revoke execute on function better_supabase.ensure_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.ensure_job_queue(text) to service_role;
revoke execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) to service_role;
revoke execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) to service_role;
revoke execute on function better_supabase.claim_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_jobs(text, integer, integer) to service_role;
revoke execute on function better_supabase.ready_job_queues(text[]) from public, anon, authenticated;
grant execute on function better_supabase.ready_job_queues(text[]) to service_role;
revoke execute on function better_supabase.complete_job(text, bigint, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_job(text, bigint, integer) to service_role;
revoke execute on function better_supabase.fail_job(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_job(text, bigint, integer, text, integer) to service_role;
revoke execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) to service_role;
revoke execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) to service_role;
revoke execute on function better_supabase.schedule_has_work(text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_has_work(text) to service_role;
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
revoke execute on function better_supabase.http_tick() from public, anon, authenticated;
grant execute on function better_supabase.http_tick() to service_role;
revoke execute on function better_supabase.claim_lease(text, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_lease(text, text, integer) to service_role;
revoke execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.complete_lease(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_lease(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.release_lease_claim(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_lease_claim(text, text, uuid) to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block-data queue
-- @bsb-hash sha256:fa8ce95b3ded0ed37ebd683153a0c9146ca7c434b373a882f59229e979c21151
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 14, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block queue@14 managed
-- @bsb-hash sha256:c139c6be1f5031c83e1fe6bbc28f7abfd8219c71f74b151ee64498fa806ddb1f
-- Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Functions of the earlier table-based queue (better_supabase.jobs is left in place).

-- enqueue_job before dedupe_running.

-- schedule_job before time zones.

-- purge_job_archive before dead letters had their own retention.

-- schedule_job before schedules had a tenant.

-- claim_due_schedules returns first_after now; create or replace can't change a return type.


-- Supabase Queues. Messages are {payload, max_attempts, dedupe_key?, last_error?};
-- pgmq's read_ct is the attempt number and vt the lease.
create extension if not exists pgmq;

-- Wakes listenForWork (better-supabase/postgres) on channel better_supabase_work.
create or replace function better_supabase.job_queue_notify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', pg_catalog.json_build_object('kind', 'queue', 'queue', tg_argv[0])::text);
  end if;
  return null;
end;
$$;
revoke all on function better_supabase.job_queue_notify() from public;

-- Deduplicated enqueues look the key up under an advisory lock, so each
-- queue table and its archive (enqueue_job_once) get a partial index on it.
-- Each queue table also gets the statement trigger that notifies
-- better_supabase_work.
create or replace function better_supabase.index_job_queue(queue text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  execute format(
    'create or replace trigger bsb_notify_work after insert on pgmq.%I referencing new table as new_rows for each statement execute function better_supabase.job_queue_notify(%L)',
    'q_' || queue,
    queue
  );
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
-- returns its id, and a waiting message moves to the earlier of its time and
-- the new delay. With dedupe_running false only a message no worker has
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
      -- A message nobody has read yet moves earlier when this enqueue is due
      -- sooner, never later.
      execute format('update pgmq.%I set vt = least(vt, clock_timestamp() + make_interval(secs => $2)) where msg_id = $1 and read_ct = 0', 'q_' || queue)
        using existing, greatest(delay, 0);
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

-- The queues among queues that have a message claim_jobs takes now, so a
-- drain skips the empty ones in one round trip. A queue without its pgmq
-- table has none.
create or replace function better_supabase.ready_job_queues(queues text[])
returns table (queue text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_ready boolean;
begin
  foreach v_name in array coalesce(queues, '{}') loop
    if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || v_name)) is not null then
      execute format('select exists (select 1 from pgmq.%I where vt <= clock_timestamp())', 'q_' || v_name)
        into v_ready;
      if v_ready then
        queue := v_name;
        return next;
      end if;
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
  null;
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

create or replace function better_supabase.schedule_has_work(probe text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_probe regprocedure := pg_catalog.to_regprocedure(probe || '()');
  v_work boolean;
begin
  if v_probe is null then
    return true;
  end if;
  execute format('select %s()', v_probe::oid::regproc) into v_work;
  return coalesce(v_work, true);
exception when others then
  return true;
end;
$$;

-- Recurring jobs with pg_cron, in cron.timezone (UTC unless the project changed it):
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
  tenant text default null,
  probe text default null
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
  end if;
  perform better_supabase.ensure_job_queue(queue);
  if probe is not null and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(probe || '()') and p.prorettype = 'boolean'::regtype
  ) then
    raise exception 'The probe % is not a function without arguments that returns boolean', probe using errcode = '22023';
  end if;
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text)
      || case when probe is null then '' else format(' where better_supabase.schedule_has_work(%L)', probe) end;
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
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
  v_found boolean;
  v_removed boolean;
begin
  if v_unschedule is null or v_jobs is null then
    return false;
  end if;
  -- cron.unschedule raises for a name it doesn't know.
  execute format('select exists (select 1 from %s j where j.jobname = $1)', v_jobs)
    into v_found
    using job_name;
  if not v_found then
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
-- payload, tenant or next run, so those are null.
create or replace function better_supabase.list_schedules(name_prefix text default null, for_tenant text default null)
returns table (job_name text, schedule text, timezone text, queue text, tenant text, next_run timestamptz, last_run timestamptz, lock_expires_at timestamptz, created_at timestamptz, payload jsonb, probe text)
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
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb, null::text
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

-- Supabase Cron as the clock: with blocks.queue.options.httpTick, pg_cron calls
-- this every minute (job bsb_jobs_tick). It posts to the URL in the Vault secret
-- jobs_tick_url (the drain route on pgmq, jobs.schedulesRoute on Vercel Queues)
-- with the bearer token in jobs_tick_token, usually CRON_SECRET. Returns the
-- pg_net request id, or null with a warning while a secret is missing.
create or replace function better_supabase.http_tick()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- pg_net and Vault are looked up, not named, so plpgsql_check (supabase db
  -- lint) passes without them.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
  v_url text;
  v_token text;
  v_id bigint;
begin
  if v_post is null then
    raise exception 'the queue tick needs pg_net: create extension pg_net'
      using hint = 'QUEUE_TICK_NO_PG_NET';
  end if;
  if pg_catalog.to_regclass('vault.decrypted_secrets') is null then
    raise exception 'the queue tick reads its URL and token from Vault: create extension supabase_vault'
      using hint = 'QUEUE_TICK_NO_VAULT';
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_url using 'jobs_tick_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1'
    into v_token using 'jobs_tick_token';
  if coalesce(v_url, '') = '' or coalesce(v_token, '') = '' then
    raise warning 'http_tick skipped: set the Vault secrets jobs_tick_url and jobs_tick_token';
    return null;
  end if;
  execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
    into v_id
    using v_url, '{}'::jsonb, jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_token
    ), 55000;
  return v_id;
end;
$$;

-- Leases: claim_lease answers claimed (the caller holds it until expires_at),
-- busy (another holder does; retry_after_ms says when it ends) or completed
-- (a holder finished it, and it stays finished until its keep time ends).
create table "better_supabase"."job_leases" (
  "scope" text not null default '',
  "key" text not null,
  "holder" uuid not null,
  "state" text not null default 'held' constraint bsb_job_leases_state_check check ("state" in ('held', 'completed')),
  "expires_at" timestamptz not null,
  primary key ("scope", "key")
);
alter table "better_supabase"."job_leases" enable row level security;
revoke all on "better_supabase"."job_leases" from public, anon, authenticated;
grant all on "better_supabase"."job_leases" to service_role;

create or replace function better_supabase.claim_lease(scope text, key text, lease_seconds integer default 60)
returns table (lease_state text, lease_holder uuid, lease_expires_at timestamptz, retry_after_ms integer)
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  lease_expires_at timestamptz := now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1));
  taken "better_supabase"."job_leases"%rowtype;
begin
  -- A held lease that ran out, or a completed one past its keep time, is taken
  -- over; the new holder token makes the former holder's calls return false.
  insert into "better_supabase"."job_leases" as l ("scope", "key", "holder", "state", "expires_at")
  values (scope, key, token, 'held', lease_expires_at)
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "state" = 'held', "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning * into taken;
  if found then
    return query select 'claimed'::text, token, lease_expires_at, 0;
    return;
  end if;

  select * into taken from "better_supabase"."job_leases" l
  where l."scope" = claim_lease.scope and l."key" = claim_lease.key;
  if not found then
    -- Released between the insert and the read: the caller can retry at once.
    return query select 'busy'::text, null::uuid, null::timestamptz, 0;
    return;
  end if;
  return query select
    case when taken."state" = 'completed' then 'completed' else 'busy' end,
    null::uuid,
    taken."expires_at",
    greatest(ceil(extract(epoch from taken."expires_at" - now()) * 1000)::integer, 0);
end;
$$;

-- Moves the expiry of a held lease the holder still has; false once it ran out
-- or another holder took it over.
create or replace function better_supabase.extend_lease_claim(scope text, key text, holder uuid, lease_seconds integer default 60)
returns boolean
language sql
set search_path = ''
as $$
  with extended as (
    update "better_supabase"."job_leases" l
    set "expires_at" = now() + make_interval(secs => greatest(coalesce(extend_lease_claim.lease_seconds, 60), 1))
    where l."scope" = extend_lease_claim.scope and l."key" = extend_lease_claim.key
      and l."holder" = extend_lease_claim.holder and l."state" = 'held'
      and l."expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$$;

-- Marks the work done: later claims answer completed for keep_seconds (a day by
-- default), then the key can be claimed again. False when another holder took
-- the lease over.
create or replace function better_supabase.complete_lease(scope text, key text, holder uuid, keep_seconds integer default 86400)
returns boolean
language sql
set search_path = ''
as $$
  with done as (
    update "better_supabase"."job_leases" l
    set "state" = 'completed',
        "expires_at" = now() + make_interval(secs => greatest(coalesce(complete_lease.keep_seconds, 86400), 1))
    where l."scope" = complete_lease.scope and l."key" = complete_lease.key
      and l."holder" = complete_lease.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from done)
$$;

-- On failure: gives the lease up so the next claim succeeds at once. False when
-- another holder has it now, or it was completed.
create or replace function better_supabase.release_lease_claim(scope text, key text, holder uuid)
returns boolean
language sql
set search_path = ''
as $$
  with released as (
    delete from "better_supabase"."job_leases" l
    where l."scope" = release_lease_claim.scope and l."key" = release_lease_claim.key
      and l."holder" = release_lease_claim.holder and l."state" = 'held'
    returning 1
  )
  select exists (select 1 from released)
$$;

revoke execute on function better_supabase.index_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.index_job_queue(text) to service_role;
revoke execute on function better_supabase.ensure_job_queue(text) from public, anon, authenticated;
grant execute on function better_supabase.ensure_job_queue(text) to service_role;
revoke execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job(text, jsonb, integer, integer, text, boolean) to service_role;
revoke execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.enqueue_job_once(text, jsonb, text, integer, integer) to service_role;
revoke execute on function better_supabase.claim_jobs(text, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_jobs(text, integer, integer) to service_role;
revoke execute on function better_supabase.ready_job_queues(text[]) from public, anon, authenticated;
grant execute on function better_supabase.ready_job_queues(text[]) to service_role;
revoke execute on function better_supabase.complete_job(text, bigint, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_job(text, bigint, integer) to service_role;
revoke execute on function better_supabase.fail_job(text, bigint, integer, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.fail_job(text, bigint, integer, text, integer) to service_role;
revoke execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_job_lease(text, bigint, integer, integer) to service_role;
revoke execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_job(text, text, text, jsonb, text, timestamptz, text, text) to service_role;
revoke execute on function better_supabase.schedule_has_work(text) from public, anon, authenticated;
grant execute on function better_supabase.schedule_has_work(text) to service_role;
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
revoke execute on function better_supabase.http_tick() from public, anon, authenticated;
grant execute on function better_supabase.http_tick() to service_role;
revoke execute on function better_supabase.claim_lease(text, text, integer) from public, anon, authenticated;
grant execute on function better_supabase.claim_lease(text, text, integer) to service_role;
revoke execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.extend_lease_claim(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.complete_lease(text, text, uuid, integer) from public, anon, authenticated;
grant execute on function better_supabase.complete_lease(text, text, uuid, integer) to service_role;
revoke execute on function better_supabase.release_lease_claim(text, text, uuid) from public, anon, authenticated;
grant execute on function better_supabase.release_lease_claim(text, text, uuid) to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_007_queue.sql
-- better-supabase module: queue
-- @bsb-block-data queue
-- @bsb-hash sha256:fa8ce95b3ded0ed37ebd683153a0c9146ca7c434b373a882f59229e979c21151
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgmq";

-- Indexes the queues that existed before the module.
select better_supabase.index_job_queue(q.queue_name) from pgmq.list_queues() q;

insert into better_supabase.blocks (name, version, mode)
values ('queue', 14, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
