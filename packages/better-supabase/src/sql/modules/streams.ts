import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";

const NAMES: ModuleNames = {
  options: ["topic"],
  tables: {
    streams: {
      name: "streams",
      lifecycle: { user: "owner", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        owner: "owner_id",
        kind: "kind",
        wake: "wake",
        createdAt: "created_at",
        closedAt: "closed_at",
        cancelRequestedAt: "cancel_requested_at",
        expiresAt: "expires_at",
      },
    },
    chunks: {
      name: "stream_chunks",
      columns: {
        stream: "stream_id",
        idx: "idx",
        data: "data",
      },
    },
  },
};

const TOPIC_PREFIX = /^[a-z][a-z0-9_-]{0,30}$/;

function topicPrefix(ctx: ModuleContext): string {
  const prefix = ctx.text("topic", "stream");
  if (!TOPIC_PREFIX.test(prefix)) {
    throw new TypeError(
      "sql.modules.streams.options.topic must be a lowercase name of at most 31 characters",
    );
  }
  return prefix;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const s = ctx.table("streams");
  const c = ctx.table("chunks");
  const cs = (column: string): string => ctx.col("streams", column);
  const cc = (column: string): string => ctx.col("chunks", column);
  const prefix = topicPrefix(ctx);
  const topic = (stream: string): string =>
    `${sqlString(`${prefix}:`)} || ${stream}`;
  const receive = ctx.trigger("streams_receive");
  const wake = (stream: string, event: string): string => `
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, ${sqlString(event)}, ${topic(stream)}, true);
  end if;`;
  const service = `revoke execute on function %s from public, anon, authenticated;
grant execute on function %s to service_role;`;
  const serviceOnly = (signature: string): string =>
    service.replaceAll("%s", signature);

  return `${schemaPreamble(ctx)}
-- Durable output streams: a writer appends ordered text chunks and any reader
-- resumes from a chunk index. The service role writes; the owner reads
-- through RLS.
create table if not exists ${s} (
  ${cs("id")} text primary key check (length(${cs("id")}) between 1 and 200),
  ${cs("tenant")} ${id},
  ${cs("owner")} uuid references auth.users (id) on delete cascade,
  ${cs("kind")} text not null default 'default' check (length(${cs("kind")}) between 1 and 100),
  ${cs("wake")} boolean not null default true,
  ${cs("createdAt")} timestamptz not null default now(),
  ${cs("closedAt")} timestamptz,
  ${cs("cancelRequestedAt")} timestamptz,
  ${cs("expiresAt")} timestamptz not null default now() + interval '1 day'
);
create index if not exists streams_owner_idx on ${s} (${cs("owner")});
create index if not exists streams_tenant_idx on ${s} (${cs("tenant")});
create index if not exists streams_expires_idx on ${s} (${cs("expiresAt")});
alter table ${s} enable row level security;
revoke all on ${s} from anon, authenticated;
grant select on ${s} to authenticated;
grant all on ${s} to service_role;
drop policy if exists streams_owner_read on ${s};
create policy streams_owner_read on ${s} for select to authenticated
  using (${cs("owner")} = (select auth.uid()));

create table if not exists ${c} (
  ${cc("stream")} text not null references ${s} (${cs("id")}) on delete cascade,
  ${cc("idx")} integer not null check (${cc("idx")} >= 0),
  ${cc("data")} text not null,
  primary key (${cc("stream")}, ${cc("idx")})
);
alter table ${c} enable row level security;
revoke all on ${c} from anon, authenticated;
grant select on ${c} to authenticated;
grant all on ${c} to service_role;
drop policy if exists stream_chunks_owner_read on ${c};
create policy stream_chunks_owner_read on ${c} for select to authenticated
  using (exists (
    select 1 from ${s} st
    where st.${cs("id")} = ${cc("stream")} and st.${cs("owner")} = (select auth.uid())
  ));

-- Opens a stream; true when it was created, false when it already existed.
-- wake = false skips the Realtime ping after each batch, for apps near the
-- Realtime message quota; readers then poll.
create or replace function ${fn("stream_open")}(stream_id text, owner uuid default null, tenant ${id} default null, kind text default 'default', ttl interval default '1 day', wake boolean default true)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_created boolean;
begin
  insert into ${s} (${cs("id")}, ${cs("owner")}, ${cs("tenant")}, ${cs("kind")}, ${cs("wake")}, ${cs("expiresAt")})
  values (stream_id, owner, tenant, coalesce(kind, 'default'), coalesce(wake, true), now() + coalesce(ttl, interval '1 day'))
  on conflict (${cs("id")}) do nothing
  returning true into v_created;
  return coalesce(v_created, false);
end;
$$;
${serviceOnly(`${fn("stream_open")}(text, uuid, ${id}, text, interval, boolean)`)}

-- Appends chunks from from_idx on. A retried batch is a no-op for the indexes
-- already stored, so a writer can resend after a timeout. Returns
-- { next, cancelled } so the writer learns of a stop without another call.
create or replace function ${fn("stream_append")}(stream_id text, from_idx integer, chunks text[])
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_stream ${s}%rowtype;
  v_next integer;
  v_wake boolean;
begin
  select * into v_stream from ${s} where ${cs("id")} = stream_append.stream_id;
  if not found then
    raise exception 'stream % does not exist', stream_append.stream_id
      using errcode = 'P0002', hint = 'STREAM_NOT_FOUND';
  end if;
  if v_stream.${cs("closedAt")} is not null then
    raise exception 'stream % is closed', stream_append.stream_id
      using errcode = 'P0001', hint = 'STREAM_CLOSED';
  end if;
  select coalesce(max(${cc("idx")}) + 1, 0) into v_next from ${c} where ${cc("stream")} = stream_append.stream_id;
  if from_idx < 0 or from_idx > v_next then
    raise exception 'stream % is at chunk %, not %', stream_append.stream_id, v_next, from_idx
      using errcode = 'P0001', hint = 'STREAM_GAP';
  end if;
  insert into ${c} (${cc("stream")}, ${cc("idx")}, ${cc("data")})
  select stream_append.stream_id, from_idx + (n.ord - 1)::integer, n.chunk
  from unnest(coalesce(chunks, '{}'::text[])) with ordinality as n(chunk, ord)
  on conflict do nothing;
  v_next := greatest(v_next, from_idx + coalesce(cardinality(chunks), 0));
  v_wake := v_stream.${cs("wake")} and coalesce(cardinality(chunks), 0) > 0;
  ${wake("stream_append.stream_id", "append")}
  return jsonb_build_object('next', v_next, 'cancelled', v_stream.${cs("cancelRequestedAt")} is not null);
end;
$$;
${serviceOnly(`${fn("stream_append")}(text, integer, text[])`)}

-- Up to max chunks from from_idx: { found, chunks, next, done, cancelled }.
-- done is true once the stream is closed and every chunk was read. Runs as the
-- caller, so a user only reads the streams they own.
create or replace function ${fn("stream_read")}(stream_id text, from_idx integer default 0, max integer default 1000)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_stream ${s}%rowtype;
  v_chunks text[];
  v_next integer;
  v_last integer;
begin
  select * into v_stream from ${s} where ${cs("id")} = stream_read.stream_id;
  if not found then
    return jsonb_build_object('found', false, 'chunks', '[]'::jsonb, 'next', greatest(coalesce(from_idx, 0), 0), 'done', true, 'cancelled', false);
  end if;
  select coalesce(array_agg(r.${cc("data")} order by r.${cc("idx")}), '{}'::text[]) into v_chunks
  from (
    select ${cc("data")}, ${cc("idx")} from ${c}
    where ${cc("stream")} = stream_read.stream_id and ${cc("idx")} >= greatest(coalesce(from_idx, 0), 0)
    order by ${cc("idx")}
    limit least(greatest(coalesce(max, 1000), 0), 10000)
  ) r;
  v_next := greatest(coalesce(from_idx, 0), 0) + cardinality(v_chunks);
  select coalesce(max(${cc("idx")}) + 1, 0) into v_last from ${c} where ${cc("stream")} = stream_read.stream_id;
  return jsonb_build_object(
    'found', true,
    'chunks', to_jsonb(v_chunks),
    'next', v_next,
    'done', v_stream.${cs("closedAt")} is not null and v_next >= v_last,
    'cancelled', v_stream.${cs("cancelRequestedAt")} is not null
  );
end;
$$;
revoke execute on function ${fn("stream_read")}(text, integer, integer) from public, anon;
grant execute on function ${fn("stream_read")}(text, integer, integer) to authenticated, service_role;

-- { next, closed, cancelled, expires_at } for a stream the caller can read,
-- or null.
create or replace function ${fn("stream_status")}(stream_id text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'next', (select coalesce(max(ch.${cc("idx")}) + 1, 0) from ${c} ch where ch.${cc("stream")} = st.${cs("id")}),
    'closed', st.${cs("closedAt")} is not null,
    'cancelled', st.${cs("cancelRequestedAt")} is not null,
    'kind', st.${cs("kind")},
    'expires_at', st.${cs("expiresAt")}
  )
  from ${s} st
  where st.${cs("id")} = stream_status.stream_id;
$$;
revoke execute on function ${fn("stream_status")}(text) from public, anon;
grant execute on function ${fn("stream_status")}(text) to authenticated, service_role;

-- Marks the stream finished; readers end once they reach the last chunk.
create or replace function ${fn("stream_close")}(stream_id text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  update ${s} set ${cs("closedAt")} = now()
  where ${cs("id")} = stream_close.stream_id and ${cs("closedAt")} is null
  returning ${cs("wake")} into v_wake;
  if not found then
    return false;
  end if;
  ${wake("stream_close.stream_id", "close")}
  return true;
end;
$$;
${serviceOnly(`${fn("stream_close")}(text)`)}

-- Asks the writer to stop; it sees the flag on its next append. The service
-- role or the stream's owner may call it.
create or replace function ${fn("stream_cancel")}(stream_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  update ${s} set ${cs("cancelRequestedAt")} = now()
  where ${cs("id")} = stream_cancel.stream_id
    and ${cs("cancelRequestedAt")} is null
    and ${cs("closedAt")} is null
    and (${SERVICE_CALLER} or ${cs("owner")} = (select auth.uid()))
  returning ${cs("wake")} into v_wake;
  if not found then
    return false;
  end if;
  ${wake("stream_cancel.stream_id", "cancel")}
  return true;
end;
$$;
revoke execute on function ${fn("stream_cancel")}(text) from public, anon;
grant execute on function ${fn("stream_cancel")}(text) to authenticated, service_role;

-- Deletes expired streams and closed ones older than older_than, at most
-- batch per call; their chunks go with them.
create or replace function ${fn("purge_streams")}(older_than interval default '1 day', batch integer default 1000)
returns integer
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  with doomed as (
    select ${cs("id")} from ${s}
    where ${cs("expiresAt")} <= now()
      or ${cs("closedAt")} <= now() - coalesce(older_than, interval '1 day')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from ${s} st using doomed where st.${cs("id")} = doomed.${cs("id")};
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceOnly(`${fn("purge_streams")}(interval, integer)`)}

-- The owner may join the stream's private topic to hear the payload-free
-- pings; the chunks themselves are read through RLS.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${prefix}:%`)}
        and exists (
          select 1 from ${s} st
          where st.${cs("id")} = substr((select realtime.topic()), ${String(prefix.length + 2)})
            and st.${cs("owner")} = (select auth.uid())
        )
      );
  end if;
end;
$$;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "stream_open",
      args: ["text", "uuid", "{id}", "text", "interval", "boolean"],
      returns: "boolean",
    },
    {
      name: "stream_append",
      args: ["text", "integer", "text[]"],
      returns: "jsonb",
    },
    {
      name: "stream_read",
      args: ["text", "integer", "integer"],
      returns: "jsonb",
    },
    { name: "stream_status", args: ["text"], returns: "jsonb" },
    { name: "stream_close", args: ["text"], returns: "boolean" },
    { name: "stream_cancel", args: ["text"], returns: "boolean" },
    {
      name: "purge_streams",
      args: ["interval", "integer"],
      returns: "integer",
    },
  ];
}

export const STREAMS: ModuleDefinition = {
  name: "streams",
  title: "Durable streams",
  description:
    "Ordered text chunks a writer appends and any reader resumes from an index: idempotent batches, a cancel flag the writer reads on its next append, owner reads through RLS, a payload-free Realtime ping on a private topic per stream, and a purge for expired streams.",
  requires: [],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  topics: (ctx) => [`${topicPrefix(ctx)}:{streamId}`],
};
