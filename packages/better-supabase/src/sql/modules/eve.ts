import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

/** The queue the projection jobs run on: one debounced job per eve session. */
const EVE_SESSION_SYNC_QUEUE = "eve_session_sync";

/** The tables of the eve projection, in the `workflow` schema. */
export const EVE_TABLES: readonly string[] = [
  "eve_sessions",
  "eve_session_runs",
];

/** The functions only the service role calls, with their argument types. */
export const EVE_SERVICE_FUNCTIONS: readonly (readonly [string, string])[] = [
  ["eve_session_wake", "text, integer"],
  ["eve_session_lease", "text, integer"],
  [
    "eve_session_commit",
    "text, text, bigint, text, text, text, text, text, text, text",
  ],
  ["eve_session_release", "text, text"],
  ["eve_sessions_behind", "interval, integer"],
  ["eve_open_sessions", "text, text, integer"],
  ["eve_session_mark", "text, text"],
];

const EVE_SESSION_STATUSES = [
  "open",
  "ended",
  "failed",
  "cancelled",
  "stranded",
] as const;

/** The two tables, created next to the World's tables so the grants cover them. */
export function eveTablesSql(): string {
  return `-- The eve projection (eve sessions copied into the blocks by syncSession).
-- session_id is the id of the session's first run. read_cursor is the next
-- line of the session stream to read. A session is behind while dirty_at is
-- later than synced_at; the lease keeps two sync jobs off one session.
create table if not exists workflow.eve_sessions (
  session_id text primary key check (length(session_id) between 1 and 200),
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint not null default 0 check (read_cursor >= 0),
  status text not null default 'open' check (status in (${EVE_SESSION_STATUSES.map((status) => `'${status}'`).join(", ")})),
  dirty_at timestamptz,
  synced_at timestamptz,
  lease_id text,
  leased_at timestamptz,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists eve_sessions_dirty_idx on workflow.eve_sessions (dirty_at) where dirty_at is not null;
create index if not exists eve_sessions_open_idx on workflow.eve_sessions (eve_version) where status = 'open';
create table if not exists workflow.eve_session_runs (
  run_id text primary key,
  session_id text not null references workflow.eve_sessions (session_id) on delete cascade,
  eve_version text,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists eve_session_runs_session_idx on workflow.eve_session_runs (session_id);`;
}

/**
 * The eve projection: which eve sessions the World holds, how far each one is
 * copied into the blocks, and the trigger that wakes a debounced sync job when
 * a session's runs or events change. A session is its first run's id; a handoff
 * successor names it in `$eve.session`.
 */
export function eveProjectionSql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const wake = fn("eve_session_wake");
  const trackRun = ctx.trigger("workflow_sdk_eve_runs");
  const trackEvent = ctx.trigger("workflow_sdk_eve_events");

  const enqueue = ctx.enqueue(
    EVE_SESSION_SYNC_QUEUE,
    "jsonb_build_object('sessionId', sid)",
    "'eve:' || sid",
    { delay: "greatest(coalesce(delay_seconds, 0), 0)" },
  );

  return `-- Marks a session as behind and queues its sync job. The job is debounced: a
-- job that has not started yet absorbs later wake-ups of the same session.
create or replace function ${wake}(sid text, delay_seconds integer default 2)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into workflow.eve_sessions as s (session_id, dirty_at) values (sid, now())
  on conflict (session_id) do update set dirty_at = now(), updated_at = now();
  ${enqueue}
end;
$$;

-- Follows eve's runs: a run with an eve session type, or one that names its
-- session, belongs to that session. The newest run decides the status.
create or replace function ${fn("workflow_sdk_track_eve_run")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
  v_status text;
begin
  if new.attributes ->> '$eve.type' is distinct from 'session' and nullif(new.attributes ->> '$eve.session', '') is null then
    return null;
  end if;
  v_session := coalesce(nullif(new.attributes ->> '$eve.session', ''), new.id);
  v_status := case new.status::text
    when 'completed' then 'ended'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'open'
  end;
  insert into workflow.eve_sessions as s (session_id, eve_version, run_id, status)
  values (v_session, new.attributes ->> '$eve.version', new.id, v_status)
  on conflict (session_id) do update set
    eve_version = coalesce(new.attributes ->> '$eve.version', s.eve_version),
    run_id = new.id,
    status = case when s.status = 'stranded' then s.status else v_status end,
    updated_at = now()
  where s.run_id is null or s.run_id = new.id
    or new.created_at >= coalesce((select r.created_at from workflow.workflow_runs r where r.id = s.run_id), '-infinity'::timestamptz);
  insert into workflow.eve_session_runs as sr (run_id, session_id, eve_version, status)
  values (new.id, v_session, new.attributes ->> '$eve.version', new.status::text)
  on conflict (run_id) do update set status = new.status::text, updated_at = now();
  perform ${wake}(v_session);
  return null;
end;
$$;
revoke execute on function ${fn("workflow_sdk_track_eve_run")}() from public, anon, authenticated;
drop trigger if exists ${trackRun} on workflow.workflow_runs;
create trigger ${trackRun} after insert or update of status on workflow.workflow_runs
  for each row execute function ${fn("workflow_sdk_track_eve_run")}();

-- Wakes the session of a run that wrote an event. Other runs cost one lookup.
create or replace function ${fn("workflow_sdk_wake_eve_session")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
begin
  select sr.session_id into v_session from workflow.eve_session_runs sr where sr.run_id = new.run_id;
  if v_session is not null then
    perform ${wake}(v_session);
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("workflow_sdk_wake_eve_session")}() from public, anon, authenticated;
drop trigger if exists ${trackEvent} on workflow.workflow_events;
create trigger ${trackEvent} after insert on workflow.workflow_events
  for each row execute function ${fn("workflow_sdk_wake_eve_session")}();

-- Takes the lease on a session and returns its row, or no row while another
-- sync job holds the lease.
create or replace function ${fn("eve_session_lease")}(sid text, lease_seconds integer default 60)
returns table (
  session_id text,
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint,
  status text,
  lease_id text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_token text := gen_random_uuid()::text;
begin
  insert into workflow.eve_sessions (session_id) values (sid) on conflict (session_id) do nothing;
  return query
    update workflow.eve_sessions s set
      lease_id = v_token,
      leased_at = now(),
      lease_until = now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1)),
      updated_at = now()
    where s.session_id = sid and (s.lease_until is null or s.lease_until < now())
    returning s.session_id, s.tenant_id, s.principal_kind, s.principal_id, s.eve_version, s.chat_id,
      s.record_type, s.record_id, s.run_id, s.read_cursor, s.status, s.lease_id;
end;
$$;

-- Advances the cursor and stores what the job resolved, then frees the lease.
-- synced_at is the time the lease began, so a change after that stays behind.
create or replace function ${fn("eve_session_commit")}(
  sid text,
  token text,
  cursor_line bigint,
  tenant text default null,
  principal_kind text default null,
  principal_id text default null,
  chat text default null,
  record_type text default null,
  record_id text default null,
  session_status text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status is not null and session_status not in (${EVE_SESSION_STATUSES.map((status) => `'${status}'`).join(", ")}) then
    raise exception 'eve_session_commit: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions s set
    read_cursor = greatest(s.read_cursor, coalesce(cursor_line, 0)),
    tenant_id = coalesce(tenant, s.tenant_id),
    principal_kind = coalesce(eve_session_commit.principal_kind, s.principal_kind),
    principal_id = coalesce(eve_session_commit.principal_id, s.principal_id),
    chat_id = coalesce(chat, s.chat_id),
    record_type = coalesce(eve_session_commit.record_type, s.record_type),
    record_id = coalesce(eve_session_commit.record_id, s.record_id),
    status = coalesce(session_status, s.status),
    synced_at = coalesce(s.leased_at, now()),
    lease_id = null,
    lease_until = null,
    updated_at = now()
  where s.session_id = sid and s.lease_id = token;
  return found;
end;
$$;

-- Frees a lease without advancing the cursor, so the next job starts at once.
create or replace function ${fn("eve_session_release")}(sid text, token text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update workflow.eve_sessions set lease_id = null, lease_until = null, updated_at = now()
  where session_id = sid and lease_id = token
  returning true;
$$;

-- The sessions whose copy is behind, oldest first: changed since the last sync,
-- or open and not synced for older_than.
create or replace function ${fn("eve_sessions_behind")}(older_than interval default '5 minutes', max integer default 100)
returns table (session_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id
  from workflow.eve_sessions s
  where (s.lease_until is null or s.lease_until < now())
    and (
      (s.dirty_at is not null and (s.synced_at is null or s.synced_at < s.dirty_at))
      or (s.status = 'open' and coalesce(s.synced_at, s.created_at) < now() - coalesce(older_than, interval '5 minutes'))
    )
  order by coalesce(s.synced_at, s.created_at)
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- The open sessions that a release other than not_version started, oldest first.
create or replace function ${fn("eve_open_sessions")}(not_version text default null, tenant text default null, max integer default 100)
returns table (
  session_id text,
  eve_version text,
  tenant_id text,
  principal_id text,
  chat_id text,
  run_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id, s.eve_version, s.tenant_id, s.principal_id, s.chat_id, s.run_id, s.created_at
  from workflow.eve_sessions s
  where s.status = 'open'
    and (not_version is null or s.eve_version is distinct from not_version)
    and (tenant is null or s.tenant_id = tenant)
  order by s.created_at
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- Sets a session's status (for instance stranded) and queues a sync.
create or replace function ${fn("eve_session_mark")}(sid text, session_status text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status not in (${EVE_SESSION_STATUSES.map((status) => `'${status}'`).join(", ")}) then
    raise exception 'eve_session_mark: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions set status = session_status, updated_at = now() where session_id = sid;
  if not found then
    return false;
  end if;
  perform ${wake}(sid, 0);
  return true;
end;
$$;`;
}

export function eveContract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "eve_session_wake", args: ["text", "integer"], returns: "void" },
    { name: "eve_session_lease", args: ["text", "integer"], returns: "record" },
    {
      name: "eve_session_commit",
      args: [
        "text",
        "text",
        "bigint",
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
        "text",
      ],
      returns: "boolean",
    },
    { name: "eve_session_release", args: ["text", "text"], returns: "boolean" },
    {
      name: "eve_sessions_behind",
      args: ["interval", "integer"],
      returns: "record",
    },
    {
      name: "eve_open_sessions",
      args: ["text", "text", "integer"],
      returns: "record",
    },
    { name: "eve_session_mark", args: ["text", "text"], returns: "boolean" },
  ];
}
