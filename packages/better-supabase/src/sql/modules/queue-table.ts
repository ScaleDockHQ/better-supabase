import type { BlockSqlContext, BlockSqlTableSpec } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { revokeTable } from "../shared.ts";

/** `names.tables.messages`: the table backend's messages. */
export const MESSAGES_TABLE: BlockSqlTableSpec = {
  name: "job_messages",
  app: { writes: false },
  columns: {
    id: "id",
    queue: "queue",
    message: "message",
    attempts: "attempts",
    enqueuedAt: "enqueued_at",
    visibleAt: "visible_at",
    archivedAt: "archived_at",
    dead: "dead",
    dedupeKey: "dedupe_key",
    maxAttempts: "max_attempts",
  },
};

/** The table backend; `guard` opens `purge_job_archive` (see `archiveGuard`). */
export function table(ctx: BlockSqlContext, guard: string): string {
  const messages = ctx.table("messages");
  const c = (column: string): string => ctx.col("messages", column);
  const { schema, name } = ctx.tableName("messages");
  const index = (what: string): string => sqlIdent(`${name}_${what}`);

  // The dedupe index before it allowed a follow-up behind a claimed message.
  const legacy = ctx.owns("messages")
    ? `\ndrop index if exists ${sqlIdent(schema)}.${index("dedupe_idx")};`
    : "";

  return `-- Jobs in a plain table, for projects without pgmq. Messages have the same
-- {payload, max_attempts, dedupe_key?, last_error?} body as on pgmq; claims
-- take rows with for update skip locked, and attempts is the lease token.
create table if not exists ${messages} (
  ${c("id")} bigint generated always as identity primary key,
  ${c("queue")} text not null check (${c("queue")} ~ '^[a-z_][a-z0-9_]{0,46}$'),
  ${c("message")} jsonb not null,
  ${c("attempts")} integer not null default 0,
  ${c("enqueuedAt")} timestamptz not null default now(),
  ${c("visibleAt")} timestamptz not null default now(),
  ${c("archivedAt")} timestamptz,
  ${c("dead")} boolean not null default false,
  ${c("dedupeKey")} text generated always as (${c("message")} ->> 'dedupe_key') stored
);
create index if not exists ${index("ready_idx")}
  on ${messages} (${c("queue")}, ${c("visibleAt")}) where ${c("archivedAt")} is null;
-- One waiting message per dedupe key; a claimed one can have a follow-up
-- queued behind it (enqueue_job with dedupe_running false).${legacy}
create unique index if not exists ${index("waiting_dedupe_idx")}
  on ${messages} (${c("queue")}, ${c("dedupeKey")}) where ${c("archivedAt")} is null and ${c("dedupeKey")} is not null and ${c("attempts")} = 0;
create index if not exists ${index("dedupe_lookup_idx")}
  on ${messages} (${c("queue")}, ${c("dedupeKey")}) where ${c("archivedAt")} is null and ${c("dedupeKey")} is not null;
create index if not exists ${index("dedupe_once_idx")}
  on ${messages} (${c("queue")}, ${c("dedupeKey")}) where ${c("dedupeKey")} is not null;
create index if not exists ${index("archived_idx")}
  on ${messages} (${c("queue")}, ${c("archivedAt")}) where ${c("archivedAt")} is not null;
-- The message's attempt limit as a column, so claims find messages whose
-- lease ran out on the last attempt through an index.
alter table ${messages} add column if not exists ${c("maxAttempts")} integer
  generated always as (coalesce((${c("message")} ->> 'max_attempts')::integer, 5)) stored;
create index if not exists ${index("exhausted_idx")}
  on ${messages} (${c("queue")}, ${c("visibleAt")}) where ${c("archivedAt")} is null and ${c("attempts")} >= ${c("maxAttempts")};
alter table ${messages} enable row level security;
${revokeTable(messages)}

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
    select m.${c("id")} into existing
    from ${messages} m
    where m.${c("queue")} = enqueue_job.queue and m.${c("dedupeKey")} = enqueue_job.dedupe_key and m.${c("archivedAt")} is null
      and (enqueue_job.dedupe_running or m.${c("attempts")} = 0)
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into ${messages} (${c("queue")}, ${c("message")}, ${c("visibleAt")})
  values (
    queue,
    jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
      || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
    clock_timestamp() + make_interval(secs => greatest(delay, 0))
  )
  returning ${c("id")} into created;
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
  select m.${c("id")} into existing
  from ${messages} m
  where m.${c("queue")} = enqueue_job_once.queue and m.${c("dedupeKey")} = enqueue_job_once.dedupe_key
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
  update ${messages} m
  set ${c("message")} = m.${c("message")} || jsonb_build_object('last_error', 'The lease ran out on the last attempt', 'dead', true),
      ${c("dead")} = true,
      ${c("archivedAt")} = now()
  where m.${c("queue")} = claim_jobs.queue and m.${c("archivedAt")} is null and m.${c("visibleAt")} <= v_now
    and m.${c("attempts")} >= m.${c("maxAttempts")};
  return query
    with picked as (
      select m.${c("id")} as id
      from ${messages} m
      where m.${c("queue")} = claim_jobs.queue and m.${c("archivedAt")} is null and m.${c("visibleAt")} <= v_now
      order by m.${c("visibleAt")}, m.${c("id")}
      limit greatest(batch, 1)
      for update skip locked
    )
    update ${messages} m
    set ${c("attempts")} = m.${c("attempts")} + 1,
        ${c("visibleAt")} = v_now + make_interval(secs => lease)
    from picked
    where m.${c("id")} = picked.id
    returning m.${c("id")}, m.${c("attempts")}, m.${c("enqueuedAt")}, m.${c("visibleAt")}, m.${c("message")};
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
    update ${messages} m
    set ${c("archivedAt")} = now()
    where m.${c("id")} = complete_job.job_id and m.${c("queue")} = complete_job.queue and m.${c("attempts")} = complete_job.attempt and m.${c("archivedAt")} is null
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
  select m.${c("message")} into msg
  from ${messages} m
  where m.${c("id")} = fail_job.job_id and m.${c("queue")} = fail_job.queue and m.${c("attempts")} = fail_job.attempt and m.${c("archivedAt")} is null
  for update;
  if msg is null then
    return null;
  end if;
  if attempt >= coalesce((msg ->> 'max_attempts')::integer, 5) then
    update ${messages} m
    set ${c("message")} = m.${c("message")} || jsonb_build_object('last_error', left(error, 4000), 'dead', true),
        ${c("dead")} = true,
        ${c("archivedAt")} = now()
    where m.${c("id")} = fail_job.job_id;
    return 'dead';
  end if;
  update ${messages} m
  set ${c("message")} = m.${c("message")} || jsonb_build_object('last_error', left(error, 4000)),
      ${c("visibleAt")} = clock_timestamp() + make_interval(secs => coalesce(retry_in, 1 + floor(random() * least(3600, 10 * power(2, attempt - 1)))::integer))
  where m.${c("id")} = fail_job.job_id;
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
    update ${messages} m
    set ${c("visibleAt")} = clock_timestamp() + make_interval(secs => lease)
    where m.${c("id")} = extend_job_lease.job_id and m.${c("queue")} = extend_job_lease.queue and m.${c("attempts")} = extend_job_lease.attempt and m.${c("archivedAt")} is null
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
    delete from ${messages}
    where ${c("id")} in (
      select m.${c("id")} from ${messages} m
      where m.${c("queue")} = purge_job_archive.queue
        and m.${c("archivedAt")} < now() - least(older_than, dead_older_than)
        and m.${c("archivedAt")} < now() - case when m.${c("dead")} then dead_older_than else older_than end
      order by m.${c("id")}
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
  delete from ${messages} m
  where m.${c("id")} = replay_dead_job.job_id and m.${c("queue")} = replay_dead_job.queue and m.${c("dead")}
  returning m.${c("message")} into msg;
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
    count(*) filter (where m.${c("archivedAt")} is null and m.${c("visibleAt")} <= clock_timestamp()),
    count(*) filter (where m.${c("archivedAt")} is null and m.${c("visibleAt")} > clock_timestamp() and m.${c("attempts")} > 0),
    count(*) filter (where m.${c("archivedAt")} is null and m.${c("visibleAt")} > clock_timestamp() and m.${c("attempts")} = 0),
    count(*) filter (where m.${c("dead")}),
    extract(epoch from clock_timestamp() - min(m.${c("enqueuedAt")}) filter (where m.${c("archivedAt")} is null))::double precision
  from ${messages} m
  where m.${c("queue")} = job_queue_stats.queue;
$$;

-- A queue's dead letters, newest first, before before_id when given.
create or replace function better_supabase.list_dead_jobs(queue text, max_rows integer default 100, before_id bigint default null)
returns table (id bigint, attempts integer, enqueued_at timestamptz, died_at timestamptz, message jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select m.${c("id")}, m.${c("attempts")}, m.${c("enqueuedAt")}, m.${c("archivedAt")}, m.${c("message")}
  from ${messages} m
  where m.${c("queue")} = list_dead_jobs.queue and m.${c("dead")}
    and (before_id is null or m.${c("id")} < before_id)
  order by m.${c("id")} desc
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
}
