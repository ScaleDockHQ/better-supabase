import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  schemaPreamble,
  SERVICE_CALLER,
  pageSize,
  revokeTable,
} from "../shared.ts";

const NAMES: BlockSqlNames = {
  options: ["topic", "purgeSchedule", "purgeOlderThan"],
  tables: {
    streams: {
      name: "streams",
      app: {},
      lifecycle: { user: "owner", tenant: "tenant" },
      optional: ["kind", "wake", "createdAt"],
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
      app: {},
      columns: { stream: "stream_id", idx: "idx", data: "data" },
    },
    kv: {
      name: "stream_entries",
      app: {},
      columns: { key: "key", value: "value", expiresAt: "expires_at" },
    },
  },
};

const TOPIC_PREFIX = /^[a-z][a-z0-9_-]{0,30}$/;

function topicPrefix(ctx: BlockSqlContext): string {
  const prefix = ctx.text("topic", "stream");

  if (!TOPIC_PREFIX.test(prefix)) {
    throw new TypeError(
      "blocks.streams.options.topic must be a lowercase name of at most 31 characters",
    );
  }

  return prefix;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const s = ctx.table("streams");
  const c = ctx.table("chunks");
  const cs = (column: string): string => ctx.col("streams", column);
  const cc = (column: string): string => ctx.col("chunks", column);
  const prefix = topicPrefix(ctx);
  const has = (column: string): boolean => ctx.has("streams", column);

  const wakes = (alias: string): string =>
    has("wake") ? `${alias}${cs("wake")}` : "true";

  const opened = (
    [
      ["id", "stream_id"],
      ["owner", "owner"],
      ["tenant", "tenant"],
      ["kind", "coalesce(kind, 'default')"],
      ["wake", "coalesce(wake, true)"],
      ["expiresAt", "now() + coalesce(ttl, interval '1 day')"],
    ] as const
  ).filter(([column]) => ctx.has("streams", column));

  const streamsKey = ctx.owns("streams")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("streams").name}_id_key`)} on ${s} (${cs("id")});`;

  const chunksKey = ctx.owns("chunks")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("chunks").name}_idx_key`)} on ${c} (${cc("stream")}, ${cc("idx")});`;

  const kvKey = ctx.owns("kv")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("kv").name}_key_key`)} on ${ctx.table("kv")} (${ctx.col("kv", "key")});`;

  const topic = (stream: string): string =>
    `${sqlString(`${prefix}:`)} || ${stream}`;

  const receive = ctx.trigger("streams_receive");
  const kv = ctx.table("kv");
  const ck = (column: string): string => ctx.col("kv", column);
  const purgeSchedule = ctx.text("purgeSchedule", "");
  const purgeOlderThan = ctx.text("purgeOlderThan", "1 day");

  const purgeJob =
    purgeSchedule === ""
      ? ""
      : `
-- Purges on ${sqlString(purgeSchedule)} with pg_cron when the extension exists.
do $bsb$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is not null then
    execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-purge-streams', ${sqlString(purgeSchedule)}, ${sqlString(`select ${fn("purge_streams")}(${sqlString(purgeOlderThan)}::interval)`)});
  end if;
end
$bsb$;`;

  const wake = (stream: string, event: string): string => `
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, ${sqlString(event)}, ${topic(stream)}, true);
  end if;`;

  const service = `revoke execute on function %s from public, anon, authenticated;
grant execute on function %s to service_role;`;

  const serviceOnly = (signature: string): string =>
    service.replaceAll("%s", signature);

  return `${schemaPreamble(ctx)}
-- Durable output streams: a writer appends ordered chunks (bytea) and any reader
-- resumes from a chunk index. The service role writes; the owner reads
-- through RLS.
create table if not exists ${s} (
  ${cs("id")} text primary key check (length(${cs("id")}) between 1 and 200),
  ${cs("tenant")} ${id},
  ${cs("owner")} uuid references auth.users (id) on delete cascade,
${has("kind") ? `  ${cs("kind")} text not null default 'default' check (length(${cs("kind")}) between 1 and 100),\n` : ""}${has("wake") ? `  ${cs("wake")} boolean not null default true,\n` : ""}${has("createdAt") ? `  ${cs("createdAt")} timestamptz not null default now(),\n` : ""}  ${cs("closedAt")} timestamptz,
  ${cs("cancelRequestedAt")} timestamptz,
  ${cs("expiresAt")} timestamptz not null default now() + interval '1 day'
);
create index if not exists streams_owner_idx on ${s} (${cs("owner")});
create index if not exists streams_tenant_idx on ${s} (${cs("tenant")});
create index if not exists streams_expires_idx on ${s} (${cs("expiresAt")});${streamsKey}
alter table ${s} enable row level security;
${revokeTable(s)}
grant select on ${s} to authenticated;
grant all on ${s} to service_role;
${renderPolicy(makePolicy({ table: s, name: "streams_owner_read", command: "select", roles: ["authenticated"], using: `${cs("owner")} = (select auth.uid())` }), { target: s })}

create table if not exists ${c} (
  ${cc("stream")} text not null references ${s} (${cs("id")}) on delete cascade,
  ${cc("idx")} integer not null check (${cc("idx")} >= 0),
  ${cc("data")} bytea not null,
  primary key (${cc("stream")}, ${cc("idx")})
);${chunksKey}
alter table ${c} enable row level security;
${revokeTable(c)}
grant select on ${c} to authenticated;
grant all on ${c} to service_role;
${renderPolicy(
  makePolicy({
    table: c,
    name: "stream_chunks_owner_read",
    command: "select",
    roles: ["authenticated"],
    using: `exists (
    select 1 from ${s} st
    where st.${cs("id")} = ${cc("stream")} and st.${cs("owner")} = (select auth.uid())
  )`,
  }),
  { target: c },
)}

-- A key-value table with the Redis semantics resumable-stream needs from its
-- publisher (get, set with a TTL, incr), for postgresPublisher. A value that is
-- not an integer makes stream_kv_incr fail with Redis's own error text, which
-- is how the package learns a stream is DONE. The service role only.
create table if not exists ${kv} (
  ${ck("key")} text primary key check (length(${ck("key")}) between 1 and 400),
  ${ck("value")} text not null,
  ${ck("expiresAt")} timestamptz
);
create index if not exists stream_entries_expires_idx on ${kv} (${ck("expiresAt")}) where ${ck("expiresAt")} is not null;${kvKey}
alter table ${kv} enable row level security;
${revokeTable(kv)}
grant all on ${kv} to service_role;

create or replace function ${fn("stream_kv_get")}(key text)
returns text
language sql
stable
set search_path = ''
as $$
  select k.${ck("value")} from ${kv} k
  where k.${ck("key")} = stream_kv_get.key
    and (k.${ck("expiresAt")} is null or k.${ck("expiresAt")} > now());
$$;
${serviceOnly(`${fn("stream_kv_get")}(text)`)}

create or replace function ${fn("stream_kv_set")}(key text, value text, ex integer default null)
returns text
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into ${kv} (${ck("key")}, ${ck("value")}, ${ck("expiresAt")})
  values (key, value, case when ex is null then null else now() + make_interval(secs => ex) end)
  on conflict (${ck("key")}) do update
    set ${ck("value")} = excluded.${ck("value")}, ${ck("expiresAt")} = excluded.${ck("expiresAt")};
  return 'OK';
end;
$$;
${serviceOnly(`${fn("stream_kv_set")}(text, text, integer)`)}

create or replace function ${fn("stream_kv_incr")}(key text)
returns bigint
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_value text;
  v_next bigint;
begin
  delete from ${kv} where ${ck("key")} = stream_kv_incr.key and ${ck("expiresAt")} <= now();
  insert into ${kv} (${ck("key")}, ${ck("value")}) values (key, '1')
  on conflict (${ck("key")}) do nothing
  returning ${ck("value")} into v_value;
  if found then
    return 1;
  end if;
  select ${ck("value")} into v_value from ${kv} where ${ck("key")} = stream_kv_incr.key for update;
  if v_value !~ '^-?[0-9]{1,18}$' then
    raise exception 'ERR value is not an integer or out of range' using errcode = '22023';
  end if;
  v_next := v_value::bigint + 1;
  update ${kv} set ${ck("value")} = v_next::text where ${ck("key")} = stream_kv_incr.key;
  return v_next;
end;
$$;
${serviceOnly(`${fn("stream_kv_incr")}(text)`)}

-- Sends message on a private Realtime topic; the subscriber joins it with a
-- service-role client. Returns the number of listeners it can't know: 0.
create or replace function ${fn("stream_kv_publish")}(channel text, message text)
returns integer
language plpgsql
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    raise exception 'stream_kv_publish needs Supabase Realtime (realtime.send)';
  end if;
  perform realtime.send(jsonb_build_object('message', message), 'message', channel, true);
  return 0;
end;
$$;
${serviceOnly(`${fn("stream_kv_publish")}(text, text)`)}

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
  insert into ${s} (${opened.map(([column]) => cs(column)).join(", ")})
  values (${opened.map(([, value]) => value).join(", ")})
  on conflict (${cs("id")}) do nothing
  returning true into v_created;
  return coalesce(v_created, false);
end;
$$;
${serviceOnly(`${fn("stream_open")}(text, uuid, ${id}, text, interval, boolean)`)}

-- Appends chunks from from_idx on. A retried batch is a no-op for the indexes
-- already stored, so a writer can resend after a timeout. Returns
-- { next, cancelled } so the writer learns of a stop without another call.
create or replace function ${fn("stream_append")}(stream_id text, from_idx integer, chunks bytea[])
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
  from unnest(coalesce(chunks, '{}'::bytea[])) with ordinality as n(chunk, ord)
  on conflict do nothing;
  v_next := greatest(v_next, from_idx + coalesce(cardinality(chunks), 0));
  v_wake := ${wakes("v_stream.")} and coalesce(cardinality(chunks), 0) > 0;
  ${wake("stream_append.stream_id", "append")}
  return jsonb_build_object('next', v_next, 'cancelled', v_stream.${cs("cancelRequestedAt")} is not null);
end;
$$;
${serviceOnly(`${fn("stream_append")}(text, integer, bytea[])`)}

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
  select coalesce(array_agg(replace(encode(r.${cc("data")}, 'base64'), E'\n', '') order by r.${cc("idx")}), '{}'::text[]) into v_chunks
  from (
    select ${cc("data")}, ${cc("idx")} from ${c}
    where ${cc("stream")} = stream_read.stream_id and ${cc("idx")} >= greatest(coalesce(from_idx, 0), 0)
    order by ${cc("idx")}
    limit ${pageSize("max", 1000, 10_000, 0)}
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
    'kind', ${has("kind") ? `st.${cs("kind")}` : "'default'"},
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
  returning ${wakes("")} into v_wake;
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
  returning ${wakes("")} into v_wake;
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
  delete from ${kv} where ${ck("expiresAt")} <= now();
  return v_count;
end;
$$;
${serviceOnly(`${fn("purge_streams")}(interval, integer)`)}

-- The owner may join the stream's private topic to hear the payload-free
-- pings; the chunks themselves are read through RLS.
do $$
begin
  if to_regclass('realtime.messages') is not null then
        ${renderPolicy(
          makePolicy({
            table: "realtime.messages",
            name: receive,
            command: "select",
            roles: ["authenticated"],
            using: `realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like ${sqlString(`${prefix}:%`)}
        and exists (
          select 1 from ${s} st
          where st.${cs("id")} = substr((select realtime.topic()), ${String(prefix.length + 2)})
            and st.${cs("owner")} = (select auth.uid())
        )`,
          }),
          { target: "realtime.messages" },
        )}
  end if;
end;
$$;${purgeJob}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "stream_open",
      args: ["text", "uuid", "{id}", "text", "interval", "boolean"],
      returns: "boolean",
    },
    {
      name: "stream_append",
      args: ["text", "integer", "bytea[]"],
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
    { name: "stream_kv_get", args: ["text"], returns: "text" },
    {
      name: "stream_kv_set",
      args: ["text", "text", "integer"],
      returns: "text",
    },
    { name: "stream_kv_incr", args: ["text"], returns: "bigint" },
    { name: "stream_kv_publish", args: ["text", "text"], returns: "integer" },
  ];
}

export const STREAMS: BlockSqlDefinition = {
  name: "streams",
  title: "Durable streams",
  description:
    "Ordered byte chunks a writer appends and any reader resumes from an index: idempotent batches, a cancel flag the writer reads on its next append, owner reads through RLS, a payload-free Realtime ping on a private topic per stream, and a purge for expired streams.",
  requires: [],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "Chunks are bytea: stream_append takes bytea[] and stream_read returns base64 text, so binary frames survive.",
      sql: (ctx) => `do $bsb$
begin
  if (select a.atttypid from pg_attribute a where a.attrelid = ${sqlString(ctx.table("chunks"))}::regclass and a.attname = ${sqlString(ctx.col("chunks", "data").replaceAll('"', ""))}) = 'text'::regtype then
    alter table ${ctx.table("chunks")} alter column ${ctx.col("chunks", "data")} type bytea using convert_to(${ctx.col("chunks", "data")}, 'UTF8');
  end if;
end
$bsb$;
drop function if exists ${ctx.fn("stream_append")}(text, integer, text[]);`,
    },
    {
      from: 2,
      description:
        "Adds stream_entries and the stream_kv_get, stream_kv_set, stream_kv_incr and stream_kv_publish functions for postgresPublisher, and the purgeSchedule option; purge_streams also clears expired keys.",
      sql: () =>
        "-- Version 3 only adds objects; the module file below creates them.",
    },
  ],
  names: NAMES,
  contract,
  build,
  topics: (ctx) => [`${topicPrefix(ctx)}:{streamId}`],
};
