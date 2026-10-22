import { revokeTable } from "../shared.ts";

/** The table backend; `guard` opens `purge_job_archive` (see `archiveGuard`). */
export const table = (
  guard: string,
): string => `-- Jobs in a plain table, for projects without pgmq. Messages have the same
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
create index if not exists job_messages_dedupe_once_idx
  on better_supabase.job_messages (queue, dedupe_key) where dedupe_key is not null;
create index if not exists job_messages_archived_idx
  on better_supabase.job_messages (queue, archived_at) where archived_at is not null;
-- The message's attempt limit as a column, so claims find messages whose
-- lease ran out on the last attempt through an index.
alter table better_supabase.job_messages add column if not exists max_attempts integer
  generated always as (coalesce((message ->> 'max_attempts')::integer, 5)) stored;
create index if not exists job_messages_exhausted_idx
  on better_supabase.job_messages (queue, visible_at) where archived_at is null and attempts >= max_attempts;
alter table better_supabase.job_messages enable row level security;
${revokeTable("better_supabase.job_messages")}

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
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
  select m.id into existing
  from better_supabase.job_messages m
  where m.queue = enqueue_job_once.queue and m.dedupe_key = enqueue_job_once.dedupe_key
  limit 1;
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
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purged integer;
begin
  ${guard}
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
  select count(*)::integer into v_purged from purged;
  return v_purged;
end;
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
