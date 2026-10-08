-- better-supabase module: streams (0.5.1)
-- @bs-module streams@1 managed
-- Ordered text chunks a writer appends and any reader resumes from an index: idempotent batches, a cancel flag the writer reads on its next append, owner reads through RLS, a payload-free Realtime ping on a private topic per stream, and a purge for expired streams.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Durable output streams: a writer appends ordered text chunks and any reader
-- resumes from a chunk index. The service role writes; the owner reads
-- through RLS.
create table if not exists "better_supabase"."streams" (
  "id" text primary key check (length("id") between 1 and 200),
  "tenant_id" uuid,
  "owner_id" uuid references auth.users (id) on delete cascade,
  "kind" text not null default 'default' check (length("kind") between 1 and 100),
  "wake" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "closed_at" timestamptz,
  "cancel_requested_at" timestamptz,
  "expires_at" timestamptz not null default now() + interval '1 day'
);
create index if not exists streams_owner_idx on "better_supabase"."streams" ("owner_id");
create index if not exists streams_tenant_idx on "better_supabase"."streams" ("tenant_id");
create index if not exists streams_expires_idx on "better_supabase"."streams" ("expires_at");
alter table "better_supabase"."streams" enable row level security;
revoke all on "better_supabase"."streams" from anon, authenticated;
grant select on "better_supabase"."streams" to authenticated;
grant all on "better_supabase"."streams" to service_role;
drop policy if exists streams_owner_read on "better_supabase"."streams";
create policy streams_owner_read on "better_supabase"."streams" for select to authenticated
  using ("owner_id" = (select auth.uid()));

create table if not exists "better_supabase"."stream_chunks" (
  "stream_id" text not null references "better_supabase"."streams" ("id") on delete cascade,
  "idx" integer not null check ("idx" >= 0),
  "data" text not null,
  primary key ("stream_id", "idx")
);
alter table "better_supabase"."stream_chunks" enable row level security;
revoke all on "better_supabase"."stream_chunks" from anon, authenticated;
grant select on "better_supabase"."stream_chunks" to authenticated;
grant all on "better_supabase"."stream_chunks" to service_role;
drop policy if exists stream_chunks_owner_read on "better_supabase"."stream_chunks";
create policy stream_chunks_owner_read on "better_supabase"."stream_chunks" for select to authenticated
  using (exists (
    select 1 from "better_supabase"."streams" st
    where st."id" = "stream_id" and st."owner_id" = (select auth.uid())
  ));

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
create or replace function "better_supabase"."stream_append"(stream_id text, from_idx integer, chunks text[])
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
  from unnest(coalesce(chunks, '{}'::text[])) with ordinality as n(chunk, ord)
  on conflict do nothing;
  v_next := greatest(v_next, from_idx + coalesce(cardinality(chunks), 0));
  v_wake := v_stream."wake" and coalesce(cardinality(chunks), 0) > 0;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'append', 'stream:' || stream_append.stream_id, true);
  end if;
  return jsonb_build_object('next', v_next, 'cancelled', v_stream."cancel_requested_at" is not null);
end;
$$;
revoke execute on function "better_supabase"."stream_append"(text, integer, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."stream_append"(text, integer, text[]) to service_role;

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
  select coalesce(array_agg(r."data" order by r."idx"), '{}'::text[]) into v_chunks
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
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_streams"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_streams"(interval, integer) to service_role;

-- The owner may join the stream's private topic to hear the payload-free
-- pings; the chunks themselves are read through RLS.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_streams_receive" on realtime.messages;
    create policy "bs_streams_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'stream:%'
        and exists (
          select 1 from "better_supabase"."streams" st
          where st."id" = substr((select realtime.topic()), 8)
            and st."owner_id" = (select auth.uid())
        )
      );
  end if;
end;
$$;

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
