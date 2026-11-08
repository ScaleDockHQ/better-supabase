-- ==== schema supabase/schemas/900_better_supabase_040_streams.sql
-- better-supabase module: streams
-- @bsb-block streams@3 managed
-- @bsb-hash sha256:f7f66728efe8f8fc72a2d48266e87635b446420857f9aba6fe8eec954ea47a88
-- Ordered byte chunks a writer appends and any reader resumes from an index: idempotent batches, a cancel flag the writer reads on its next append, owner reads through RLS, a payload-free Realtime ping on a private topic per stream, and a purge for expired streams.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Durable output streams: a writer appends ordered chunks (bytea) and any reader
-- resumes from a chunk index. The service role writes; the owner reads
-- through RLS.
create table "better_supabase"."streams" (
  "id" text primary key constraint bsb_streams_id_check check (length("id") >= 1 and length("id") <= 200),
  "tenant_id" uuid,
  "owner_id" uuid references auth.users (id) on delete cascade,
  "kind" text not null default 'default' constraint bsb_streams_kind_check check (length("kind") >= 1 and length("kind") <= 100),
  "wake" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "closed_at" timestamptz,
  "cancel_requested_at" timestamptz,
  "expires_at" timestamptz not null default now() + interval '1 day'
);
create index streams_owner_idx on "better_supabase"."streams" ("owner_id");
create index streams_tenant_idx on "better_supabase"."streams" ("tenant_id");
create index streams_expires_idx on "better_supabase"."streams" ("expires_at");
alter table "better_supabase"."streams" enable row level security;
revoke all on "better_supabase"."streams" from public, anon, authenticated;
grant select on "better_supabase"."streams" to authenticated;
grant all on "better_supabase"."streams" to service_role;
create policy bsb_streams_owner_read on "better_supabase"."streams"
  for select to authenticated
  using ("owner_id" = (select auth.uid()));

create table "better_supabase"."stream_chunks" (
  "stream_id" text not null references "better_supabase"."streams" ("id") on delete cascade,
  "idx" integer not null constraint bsb_stream_chunks_idx_check check ("idx" >= 0),
  "data" bytea not null,
  primary key ("stream_id", "idx")
);
alter table "better_supabase"."stream_chunks" enable row level security;
revoke all on "better_supabase"."stream_chunks" from public, anon, authenticated;
grant select on "better_supabase"."stream_chunks" to authenticated;
grant all on "better_supabase"."stream_chunks" to service_role;
create policy bsb_stream_chunks_owner_read on "better_supabase"."stream_chunks"
  for select to authenticated
  using (exists (
    select 1 from "better_supabase"."streams" st
    where st."id" = "stream_id" and st."owner_id" = (select auth.uid())
  ));

-- A key-value table with the Redis semantics resumable-stream needs from its
-- publisher (get, set with a TTL, incr), for postgresPublisher. A value that is
-- not an integer makes stream_kv_incr fail with Redis's own error text, which
-- is how the package learns a stream is DONE. The service role only.
create table "better_supabase"."stream_entries" (
  "key" text primary key constraint bsb_stream_entries_key_check check (length("key") >= 1 and length("key") <= 400),
  "value" text not null,
  "expires_at" timestamptz
);
create index stream_entries_expires_idx on "better_supabase"."stream_entries" ("expires_at") where "expires_at" is not null;
alter table "better_supabase"."stream_entries" enable row level security;
revoke all on "better_supabase"."stream_entries" from public, anon, authenticated;
grant all on "better_supabase"."stream_entries" to service_role;

create or replace function "better_supabase"."stream_kv_get"(key text)
returns text
language sql
stable
set search_path = ''
as $$
  select k."value" from "better_supabase"."stream_entries" k
  where k."key" = stream_kv_get.key
    and (k."expires_at" is null or k."expires_at" > now());
$$;
revoke execute on function "better_supabase"."stream_kv_get"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_kv_get"(text) to service_role;

create or replace function "better_supabase"."stream_kv_set"(key text, value text, ex integer default null)
returns text
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into "better_supabase"."stream_entries" ("key", "value", "expires_at")
  values (key, value, case when ex is null then null else now() + make_interval(secs => ex) end)
  on conflict ("key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at";
  return 'OK';
end;
$$;
revoke execute on function "better_supabase"."stream_kv_set"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_kv_set"(text, text, integer) to service_role;

create or replace function "better_supabase"."stream_kv_incr"(key text)
returns bigint
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_value text;
  v_next bigint;
begin
  delete from "better_supabase"."stream_entries" where "key" = stream_kv_incr.key and "expires_at" <= now();
  insert into "better_supabase"."stream_entries" ("key", "value") values (key, '1')
  on conflict ("key") do nothing
  returning "value" into v_value;
  if found then
    return 1;
  end if;
  select "value" into v_value from "better_supabase"."stream_entries" where "key" = stream_kv_incr.key for update;
  if v_value !~ '^-?[0-9]{1,18}$' then
    raise exception 'ERR value is not an integer or out of range' using errcode = '22023';
  end if;
  v_next := v_value::bigint + 1;
  update "better_supabase"."stream_entries" set "value" = v_next::text where "key" = stream_kv_incr.key;
  return v_next;
end;
$$;
revoke execute on function "better_supabase"."stream_kv_incr"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_kv_incr"(text) to service_role;

-- Sends message on a private Realtime topic; the subscriber joins it with a
-- service-role client. Returns the number of listeners it can't know: 0.
create or replace function "better_supabase"."stream_kv_publish"(channel text, message text)
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
revoke execute on function "better_supabase"."stream_kv_publish"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_kv_publish"(text, text) to service_role;

-- Opens a stream; true when it was created, false when it already existed.
-- wake = false skips the Realtime ping after each batch, for apps near the
-- Realtime message quota; readers then poll.
create or replace function "better_supabase"."stream_open"(stream_id text, owner uuid default null, tenant uuid default null, kind text default 'default', ttl interval default '1 day', wake boolean default true)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_created boolean;
begin
  insert into "better_supabase"."streams" ("id", "owner_id", "tenant_id", "kind", "wake", "expires_at")
  values (stream_id, owner, tenant, coalesce(kind, 'default'), coalesce(wake, true), now() + coalesce(ttl, interval '1 day'))
  on conflict ("id") do nothing
  returning true into v_created;
  return coalesce(v_created, false);
end;
$$;
revoke execute on function "better_supabase"."stream_open"(text, uuid, uuid, text, interval, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_open"(text, uuid, uuid, text, interval, boolean) to service_role;

-- Appends chunks from from_idx on. A retried batch is a no-op for the indexes
-- already stored, so a writer can resend after a timeout. Returns
-- { next, cancelled } so the writer learns of a stop without another call.
create or replace function "better_supabase"."stream_append"(stream_id text, from_idx integer, chunks bytea[])
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_stream "better_supabase"."streams"%rowtype;
  v_next integer;
  v_wake boolean;
begin
  select * into v_stream from "better_supabase"."streams" where "id" = stream_append.stream_id;
  if not found then
    raise exception 'stream % does not exist', stream_append.stream_id
      using errcode = 'P0002', hint = 'STREAM_NOT_FOUND';
  end if;
  if v_stream."closed_at" is not null then
    raise exception 'stream % is closed', stream_append.stream_id
      using errcode = 'P0001', hint = 'STREAM_CLOSED';
  end if;
  select coalesce(max("idx") + 1, 0) into v_next from "better_supabase"."stream_chunks" where "stream_id" = stream_append.stream_id;
  if from_idx < 0 or from_idx > v_next then
    raise exception 'stream % is at chunk %, not %', stream_append.stream_id, v_next, from_idx
      using errcode = 'P0001', hint = 'STREAM_GAP';
  end if;
  insert into "better_supabase"."stream_chunks" ("stream_id", "idx", "data")
  select stream_append.stream_id, from_idx + (n.ord - 1)::integer, n.chunk
  from unnest(coalesce(chunks, '{}'::bytea[])) with ordinality as n(chunk, ord)
  on conflict do nothing;
  v_next := greatest(v_next, from_idx + coalesce(cardinality(chunks), 0));
  v_wake := v_stream."wake" and coalesce(cardinality(chunks), 0) > 0;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'append', 'stream:' || stream_append.stream_id, true);
  end if;
  return jsonb_build_object('next', v_next, 'cancelled', v_stream."cancel_requested_at" is not null);
end;
$$;
revoke execute on function "better_supabase"."stream_append"(text, integer, bytea[]) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_append"(text, integer, bytea[]) to service_role;

-- Up to max chunks from from_idx: { found, chunks, next, done, cancelled }.
-- done is true once the stream is closed and every chunk was read. Runs as the
-- caller, so a user only reads the streams they own.
create or replace function "better_supabase"."stream_read"(stream_id text, from_idx integer default 0, max integer default 1000)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_stream "better_supabase"."streams"%rowtype;
  v_chunks text[];
  v_next integer;
  v_last integer;
begin
  select * into v_stream from "better_supabase"."streams" where "id" = stream_read.stream_id;
  if not found then
    return jsonb_build_object('found', false, 'chunks', '[]'::jsonb, 'next', greatest(coalesce(from_idx, 0), 0), 'done', true, 'cancelled', false);
  end if;
  select coalesce(array_agg(replace(encode(r."data", 'base64'), E'
', '') order by r."idx"), '{}'::text[]) into v_chunks
  from (
    select "data", "idx" from "better_supabase"."stream_chunks"
    where "stream_id" = stream_read.stream_id and "idx" >= greatest(coalesce(from_idx, 0), 0)
    order by "idx"
    limit least(greatest(coalesce(max, 1000), 0), 10000)
  ) r;
  v_next := greatest(coalesce(from_idx, 0), 0) + cardinality(v_chunks);
  select coalesce(max("idx") + 1, 0) into v_last from "better_supabase"."stream_chunks" where "stream_id" = stream_read.stream_id;
  return jsonb_build_object(
    'found', true,
    'chunks', to_jsonb(v_chunks),
    'next', v_next,
    'done', v_stream."closed_at" is not null and v_next >= v_last,
    'cancelled', v_stream."cancel_requested_at" is not null
  );
end;
$$;
revoke execute on function "better_supabase"."stream_read"(text, integer, integer) from public, anon;
grant execute on function "better_supabase"."stream_read"(text, integer, integer) to authenticated, service_role;

-- { next, closed, cancelled, expires_at } for a stream the caller can read,
-- or null.
create or replace function "better_supabase"."stream_status"(stream_id text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'next', (select coalesce(max(ch."idx") + 1, 0) from "better_supabase"."stream_chunks" ch where ch."stream_id" = st."id"),
    'closed', st."closed_at" is not null,
    'cancelled', st."cancel_requested_at" is not null,
    'kind', st."kind",
    'expires_at', st."expires_at"
  )
  from "better_supabase"."streams" st
  where st."id" = stream_status.stream_id;
$$;
revoke execute on function "better_supabase"."stream_status"(text) from public, anon;
grant execute on function "better_supabase"."stream_status"(text) to authenticated, service_role;

-- Marks the stream finished; readers end once they reach the last chunk.
create or replace function "better_supabase"."stream_close"(stream_id text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  update "better_supabase"."streams" set "closed_at" = now()
  where "id" = stream_close.stream_id and "closed_at" is null
  returning "wake" into v_wake;
  if not found then
    return false;
  end if;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'close', 'stream:' || stream_close.stream_id, true);
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."stream_close"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_close"(text) to service_role;

-- Asks the writer to stop; it sees the flag on its next append. The service
-- role or the stream's owner may call it.
create or replace function "better_supabase"."stream_cancel"(stream_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."streams" set "cancel_requested_at" = now()
  where "id" = stream_cancel.stream_id
    and "cancel_requested_at" is null
    and "closed_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "owner_id" = (select auth.uid()))
  returning "wake" into v_wake;
  if not found then
    return false;
  end if;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'cancel', 'stream:' || stream_cancel.stream_id, true);
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."stream_cancel"(text) from public, anon;
grant execute on function "better_supabase"."stream_cancel"(text) to authenticated, service_role;

-- Deletes expired streams and closed ones older than older_than, at most
-- batch per call; their chunks go with them.
create or replace function "better_supabase"."purge_streams"(older_than interval default '1 day', batch integer default 1000)
returns integer
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_count integer;
begin
  with doomed as (
    select "id" from "better_supabase"."streams"
    where "expires_at" <= now()
      or "closed_at" <= now() - coalesce(older_than, interval '1 day')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."streams" st using doomed where st."id" = doomed."id";
  get diagnostics v_count = row_count;
  delete from "better_supabase"."stream_entries" where "expires_at" <= now();
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_streams"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_streams"(interval, integer) to service_role;

-- The owner may join the stream's private topic to hear the payload-free
-- pings; the chunks themselves are read through RLS.
create policy bsb_streams_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'stream:%'
        and exists (
          select 1 from "better_supabase"."streams" st
          where st."id" = substr((select realtime.topic()), 8)
            and st."owner_id" = (select auth.uid())
        ));

-- ==== data supabase/better-supabase-data/900_better_supabase_040_streams.sql
-- better-supabase module: streams
-- @bsb-block-data streams
-- @bsb-hash sha256:3bcf8a9d738998f816711012c470804d7e7c4ee577303fa3c7ed19df65969306
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('streams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
