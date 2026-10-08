-- better-supabase module: chat-sdk-state (0.5.1)
-- @bs-module chat-sdk-state@1 managed
-- The Chat SDK StateAdapter in Postgres for better-supabase/chat-sdk: thread subscriptions, token locks, a TTL cache, capped lists and per-thread queues under a key prefix, plus the bot installations per workspace with a credential_ref instead of the token. Service role only.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The Chat SDK StateAdapter in Postgres: thread subscriptions, locks with a
-- token, a key-value cache, capped lists and per-thread message queues, each
-- under a key prefix so several bots share the tables. Only the service role
-- reads and writes; better-supabase/chat-sdk's createSupabaseState() calls
-- these functions. Expired rows read as missing; purge_chat_state() deletes
-- them, e.g. from pg_cron:
--   select cron.schedule('purge-chat-state', '*/15 * * * *', 'select "better_supabase"."purge_chat_state"()');
create table if not exists "better_supabase"."chat_state_subscriptions" (
  "key_prefix" text not null,
  "thread_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("key_prefix", "thread_id")
);
alter table "better_supabase"."chat_state_subscriptions" enable row level security;
revoke all on "better_supabase"."chat_state_subscriptions" from anon, authenticated;
grant all on "better_supabase"."chat_state_subscriptions" to service_role;

create table if not exists "better_supabase"."chat_state_locks" (
  "key_prefix" text not null,
  "thread_id" text not null,
  "token" text not null,
  "expires_at" timestamptz not null,
  "updated_at" timestamptz not null default now(),
  primary key ("key_prefix", "thread_id")
);
create index if not exists chat_state_locks_expires_idx on "better_supabase"."chat_state_locks" ("expires_at");
alter table "better_supabase"."chat_state_locks" enable row level security;
revoke all on "better_supabase"."chat_state_locks" from anon, authenticated;
grant all on "better_supabase"."chat_state_locks" to service_role;

create table if not exists "better_supabase"."chat_state_cache" (
  "key_prefix" text not null,
  "cache_key" text not null,
  "value" jsonb not null,
  "expires_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  primary key ("key_prefix", "cache_key")
);
create index if not exists chat_state_cache_expires_idx on "better_supabase"."chat_state_cache" ("expires_at") where "expires_at" is not null;
alter table "better_supabase"."chat_state_cache" enable row level security;
revoke all on "better_supabase"."chat_state_cache" from anon, authenticated;
grant all on "better_supabase"."chat_state_cache" to service_role;

create table if not exists "better_supabase"."chat_state_lists" (
  "id" bigint generated always as identity primary key,
  "key_prefix" text not null,
  "list_key" text not null,
  "value" jsonb not null,
  "expires_at" timestamptz
);
create index if not exists chat_state_lists_key_idx on "better_supabase"."chat_state_lists" ("key_prefix", "list_key", "id");
create index if not exists chat_state_lists_expires_idx on "better_supabase"."chat_state_lists" ("expires_at") where "expires_at" is not null;
alter table "better_supabase"."chat_state_lists" enable row level security;
revoke all on "better_supabase"."chat_state_lists" from anon, authenticated;
grant all on "better_supabase"."chat_state_lists" to service_role;

create table if not exists "better_supabase"."chat_state_queues" (
  "id" bigint generated always as identity primary key,
  "key_prefix" text not null,
  "thread_id" text not null,
  "value" jsonb not null,
  "expires_at" timestamptz not null
);
create index if not exists chat_state_queues_thread_idx on "better_supabase"."chat_state_queues" ("key_prefix", "thread_id", "id");
create index if not exists chat_state_queues_expires_idx on "better_supabase"."chat_state_queues" ("expires_at");
alter table "better_supabase"."chat_state_queues" enable row level security;
revoke all on "better_supabase"."chat_state_queues" from anon, authenticated;
grant all on "better_supabase"."chat_state_queues" to service_role;

-- A workspace (a Slack team, a GitHub installation, a WhatsApp number) that
-- installed a bot. credential_ref names its token in a CredentialProvider;
-- the token itself never lands here. Uninstalling keeps the row, so a
-- reinstall finds its tenant, and the app revokes the credential.
create table if not exists "better_supabase"."chat_installations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "adapter" text not null check (length("adapter") between 1 and 100),
  "external_id" text not null check (length("external_id") between 1 and 500),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "metadata" jsonb not null default '{}'::jsonb,
  "installed_by" uuid references auth.users (id) on delete set null,
  "installed_at" timestamptz not null default now(),
  "uninstalled_at" timestamptz,
  unique ("adapter", "external_id")
);
create index if not exists chat_installations_tenant_idx on "better_supabase"."chat_installations" ("tenant_id");
create index if not exists chat_installations_installed_by_idx on "better_supabase"."chat_installations" ("installed_by");
alter table "better_supabase"."chat_installations" enable row level security;
revoke all on "better_supabase"."chat_installations" from anon, authenticated;
grant all on "better_supabase"."chat_installations" to service_role;

create or replace function "better_supabase"."chat_state_subscribe"(prefix text, thread_id text)
returns void
language sql
set search_path = ''
as $$
  insert into "better_supabase"."chat_state_subscriptions" ("key_prefix", "thread_id") values (prefix, thread_id)
  on conflict do nothing;
$$;
revoke execute on function "better_supabase"."chat_state_subscribe"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_subscribe"(text, text) to service_role;

create or replace function "better_supabase"."chat_state_unsubscribe"(prefix text, thread_id text)
returns void
language sql
set search_path = ''
as $$
  delete from "better_supabase"."chat_state_subscriptions" s where s."key_prefix" = chat_state_unsubscribe.prefix and s."thread_id" = chat_state_unsubscribe.thread_id;
$$;
revoke execute on function "better_supabase"."chat_state_unsubscribe"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_unsubscribe"(text, text) to service_role;

create or replace function "better_supabase"."chat_state_is_subscribed"(prefix text, thread_id text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."chat_state_subscriptions" s where s."key_prefix" = chat_state_is_subscribed.prefix and s."thread_id" = chat_state_is_subscribed.thread_id);
$$;
revoke execute on function "better_supabase"."chat_state_is_subscribed"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_is_subscribed"(text, text) to service_role;

-- Takes the thread's lock when it is free or expired: { thread_id, token,
-- expires_at }, or null while another holder's lock is live.
create or replace function "better_supabase"."chat_state_acquire_lock"(prefix text, thread_id text, token text, ttl_ms integer)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_lock "better_supabase"."chat_state_locks"%rowtype;
begin
  insert into "better_supabase"."chat_state_locks" as l ("key_prefix", "thread_id", "token", "expires_at")
  values (prefix, thread_id, token, clock_timestamp() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0))
  on conflict ("key_prefix", "thread_id") do update
    set "token" = excluded."token", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp()
    where l."expires_at" <= clock_timestamp()
  returning * into v_lock;
  if not found then
    return null;
  end if;
  return jsonb_build_object('thread_id', v_lock."thread_id", 'token', v_lock."token", 'expires_at', v_lock."expires_at");
end;
$$;
revoke execute on function "better_supabase"."chat_state_acquire_lock"(text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_acquire_lock"(text, text, text, integer) to service_role;

-- Extends a live lock the token still holds; an expired lock stays expired.
create or replace function "better_supabase"."chat_state_extend_lock"(prefix text, thread_id text, token text, ttl_ms integer)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  update "better_supabase"."chat_state_locks" l
  set "expires_at" = clock_timestamp() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0), "updated_at" = clock_timestamp()
  where l."key_prefix" = chat_state_extend_lock.prefix
    and l."thread_id" = chat_state_extend_lock.thread_id
    and l."token" = chat_state_extend_lock.token
    and l."expires_at" > clock_timestamp();
  return found;
end;
$$;
revoke execute on function "better_supabase"."chat_state_extend_lock"(text, text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_extend_lock"(text, text, text, integer) to service_role;

create or replace function "better_supabase"."chat_state_release_lock"(prefix text, thread_id text, token text)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  delete from "better_supabase"."chat_state_locks" l
  where l."key_prefix" = chat_state_release_lock.prefix
    and l."thread_id" = chat_state_release_lock.thread_id
    and l."token" = chat_state_release_lock.token;
  return found;
end;
$$;
revoke execute on function "better_supabase"."chat_state_release_lock"(text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_release_lock"(text, text, text) to service_role;

create or replace function "better_supabase"."chat_state_force_release_lock"(prefix text, thread_id text)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  delete from "better_supabase"."chat_state_locks" l
  where l."key_prefix" = chat_state_force_release_lock.prefix
    and l."thread_id" = chat_state_force_release_lock.thread_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."chat_state_force_release_lock"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_force_release_lock"(text, text) to service_role;

-- { value } for a live key, or null, so a stored JSON null stays apart from
-- a missing key.
create or replace function "better_supabase"."chat_state_get"(prefix text, key text)
returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object('value', c."value")
  from "better_supabase"."chat_state_cache" c
  where c."key_prefix" = chat_state_get.prefix and c."cache_key" = chat_state_get.key
    and (c."expires_at" is null or c."expires_at" > clock_timestamp());
$$;
revoke execute on function "better_supabase"."chat_state_get"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_get"(text, text) to service_role;

create or replace function "better_supabase"."chat_state_set"(prefix text, key text, value jsonb, ttl_ms integer default null)
returns void
language sql
set search_path = ''
as $$
  insert into "better_supabase"."chat_state_cache" ("key_prefix", "cache_key", "value", "expires_at")
  values (prefix, key, value, case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end)
  on conflict ("key_prefix", "cache_key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp();
$$;
revoke execute on function "better_supabase"."chat_state_set"(text, text, jsonb, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_set"(text, text, jsonb, integer) to service_role;

-- Writes the key unless a live value holds it; true when it wrote.
create or replace function "better_supabase"."chat_state_set_if_not_exists"(prefix text, key text, value jsonb, ttl_ms integer default null)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into "better_supabase"."chat_state_cache" as c ("key_prefix", "cache_key", "value", "expires_at")
  values (prefix, key, value, case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end)
  on conflict ("key_prefix", "cache_key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp()
    where c."expires_at" is not null and c."expires_at" <= clock_timestamp();
  return found;
end;
$$;
revoke execute on function "better_supabase"."chat_state_set_if_not_exists"(text, text, jsonb, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_set_if_not_exists"(text, text, jsonb, integer) to service_role;

create or replace function "better_supabase"."chat_state_delete"(prefix text, key text)
returns void
language sql
set search_path = ''
as $$
  delete from "better_supabase"."chat_state_cache" c where c."key_prefix" = chat_state_delete.prefix and c."cache_key" = chat_state_delete.key;
$$;
revoke execute on function "better_supabase"."chat_state_delete"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_delete"(text, text) to service_role;

-- Appends to the list, keeps the newest max_length entries and moves the
-- whole list's expiry to ttl_ms from now.
create or replace function "better_supabase"."chat_state_append_to_list"(prefix text, key text, value jsonb, max_length integer default null, ttl_ms integer default null)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_expires timestamptz := case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end;
begin
  insert into "better_supabase"."chat_state_lists" ("key_prefix", "list_key", "value", "expires_at")
  values (prefix, key, value, v_expires);
  if max_length is not null and max_length > 0 then
    delete from "better_supabase"."chat_state_lists" l
    where l."key_prefix" = chat_state_append_to_list.prefix and l."list_key" = chat_state_append_to_list.key
      and l."id" < (
        select k."id" from "better_supabase"."chat_state_lists" k
        where k."key_prefix" = chat_state_append_to_list.prefix and k."list_key" = chat_state_append_to_list.key
        order by k."id" desc
        offset max_length - 1 limit 1
      );
  end if;
  update "better_supabase"."chat_state_lists" l set "expires_at" = v_expires
  where l."key_prefix" = chat_state_append_to_list.prefix and l."list_key" = chat_state_append_to_list.key
    and l."expires_at" is distinct from v_expires;
end;
$$;
revoke execute on function "better_supabase"."chat_state_append_to_list"(text, text, jsonb, integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_append_to_list"(text, text, jsonb, integer, integer) to service_role;

create or replace function "better_supabase"."chat_state_get_list"(prefix text, key text)
returns jsonb
language sql
set search_path = ''
as $$
  select coalesce(jsonb_agg(l."value" order by l."id"), '[]'::jsonb)
  from "better_supabase"."chat_state_lists" l
  where l."key_prefix" = chat_state_get_list.prefix and l."list_key" = chat_state_get_list.key
    and (l."expires_at" is null or l."expires_at" > clock_timestamp());
$$;
revoke execute on function "better_supabase"."chat_state_get_list"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_get_list"(text, text) to service_role;

-- Queues an entry for a busy thread, keeps the newest max_size live entries
-- and returns the depth after the insert.
create or replace function "better_supabase"."chat_state_enqueue"(prefix text, thread_id text, entry jsonb, expires_at timestamptz, max_size integer default null)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_depth integer;
begin
  delete from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
    and q."expires_at" <= clock_timestamp();
  insert into "better_supabase"."chat_state_queues" ("key_prefix", "thread_id", "value", "expires_at")
  values (prefix, thread_id, entry, expires_at);
  if max_size is not null and max_size > 0 then
    delete from "better_supabase"."chat_state_queues" q
    where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
      and q."id" < (
        select k."id" from "better_supabase"."chat_state_queues" k
        where k."key_prefix" = chat_state_enqueue.prefix and k."thread_id" = chat_state_enqueue.thread_id
        order by k."id" desc
        offset max_size - 1 limit 1
      );
  end if;
  select count(*)::integer into v_depth from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
    and q."expires_at" > clock_timestamp();
  return v_depth;
end;
$$;
revoke execute on function "better_supabase"."chat_state_enqueue"(text, text, jsonb, timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_enqueue"(text, text, jsonb, timestamptz, integer) to service_role;

-- Removes and returns the oldest live entry, or null. Concurrent workers
-- skip an entry another one is taking.
create or replace function "better_supabase"."chat_state_dequeue"(prefix text, thread_id text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_value jsonb;
begin
  delete from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_dequeue.prefix and q."thread_id" = chat_state_dequeue.thread_id
    and q."expires_at" <= clock_timestamp();
  delete from "better_supabase"."chat_state_queues" q
  where q."id" = (
    select k."id" from "better_supabase"."chat_state_queues" k
    where k."key_prefix" = chat_state_dequeue.prefix and k."thread_id" = chat_state_dequeue.thread_id
    order by k."id"
    limit 1
    for update skip locked
  )
  returning q."value" into v_value;
  return v_value;
end;
$$;
revoke execute on function "better_supabase"."chat_state_dequeue"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_dequeue"(text, text) to service_role;

create or replace function "better_supabase"."chat_state_queue_depth"(prefix text, thread_id text)
returns integer
language sql
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_queue_depth.prefix and q."thread_id" = chat_state_queue_depth.thread_id
    and q."expires_at" > clock_timestamp();
$$;
revoke execute on function "better_supabase"."chat_state_queue_depth"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_state_queue_depth"(text, text) to service_role;

-- Deletes expired locks, cache keys, list entries and queued messages, at
-- most batch of each per call; returns how many rows went.
create or replace function "better_supabase"."purge_chat_state"(batch integer default 5000)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_limit integer := greatest(coalesce(batch, 5000), 1);
  v_count integer := 0;
  v_rows integer;
begin
  delete from "better_supabase"."chat_state_locks" l where ctid in (select ctid from "better_supabase"."chat_state_locks" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."chat_state_cache" c where ctid in (select ctid from "better_supabase"."chat_state_cache" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."chat_state_lists" l where l."id" in (select "id" from "better_supabase"."chat_state_lists" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."chat_state_queues" q where q."id" in (select "id" from "better_supabase"."chat_state_queues" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke execute on function "better_supabase"."purge_chat_state"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_chat_state"(integer) to service_role;

-- Records an install, or a reinstall of an uninstalled workspace, and
-- returns the row. A reinstall replaces the credential_ref; the caller
-- revokes the old one it gets back as previous_credential_ref.
create or replace function "better_supabase"."chat_install"(adapter text, external_id text, tenant uuid default null, credential_ref jsonb default null, installed_by uuid default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_previous jsonb;
  v_row "better_supabase"."chat_installations"%rowtype;
begin
  select "credential_ref" into v_previous from "better_supabase"."chat_installations"
  where "adapter" = chat_install.adapter and "external_id" = chat_install.external_id
  for update;
  insert into "better_supabase"."chat_installations" as i ("tenant_id", "adapter", "external_id", "credential_ref", "installed_by", "metadata")
  values (tenant, adapter, external_id, credential_ref, installed_by, coalesce(metadata, '{}'::jsonb))
  on conflict ("adapter", "external_id") do update
    set "tenant_id" = coalesce(excluded."tenant_id", i."tenant_id"),
        "credential_ref" = excluded."credential_ref",
        "installed_by" = coalesce(excluded."installed_by", i."installed_by"),
        "metadata" = i."metadata" || excluded."metadata",
        "installed_at" = clock_timestamp(),
        "uninstalled_at" = null
  returning * into v_row;
  return to_jsonb(v_row) || jsonb_build_object(
    'previous_credential_ref',
    case when v_previous is distinct from v_row."credential_ref" then v_previous end
  );
end;
$$;
revoke execute on function "better_supabase"."chat_install"(text, text, uuid, jsonb, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_install"(text, text, uuid, jsonb, uuid, jsonb) to service_role;

create or replace function "better_supabase"."chat_installation"(adapter text, external_id text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(i) from "better_supabase"."chat_installations" i
  where i."adapter" = chat_installation.adapter and i."external_id" = chat_installation.external_id;
$$;
revoke execute on function "better_supabase"."chat_installation"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_installation"(text, text) to service_role;

create or replace function "better_supabase"."list_chat_installations"(tenant uuid default null, adapter text default null, include_uninstalled boolean default false)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(i) order by i."installed_at" desc), '[]'::jsonb)
  from "better_supabase"."chat_installations" i
  where (list_chat_installations.tenant is null or i."tenant_id" = list_chat_installations.tenant)
    and (list_chat_installations.adapter is null or i."adapter" = list_chat_installations.adapter)
    and (coalesce(include_uninstalled, false) or i."uninstalled_at" is null);
$$;
revoke execute on function "better_supabase"."list_chat_installations"(uuid, text, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_chat_installations"(uuid, text, boolean) to service_role;

-- Marks the install removed, clears its credential_ref and returns the row
-- with the ref it held, so the caller revokes the credential. Null when
-- there was no live install.
create or replace function "better_supabase"."chat_uninstall"(adapter text, external_id text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_ref jsonb;
  v_row "better_supabase"."chat_installations"%rowtype;
begin
  select i."credential_ref" into v_ref from "better_supabase"."chat_installations" i
  where i."adapter" = chat_uninstall.adapter and i."external_id" = chat_uninstall.external_id
    and i."uninstalled_at" is null
  for update;
  if not found then
    return null;
  end if;
  update "better_supabase"."chat_installations" i set "uninstalled_at" = clock_timestamp(), "credential_ref" = null
  where i."adapter" = chat_uninstall.adapter and i."external_id" = chat_uninstall.external_id
  returning * into v_row;
  return to_jsonb(v_row) || jsonb_build_object('previous_credential_ref', v_ref);
end;
$$;
revoke execute on function "better_supabase"."chat_uninstall"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."chat_uninstall"(text, text) to service_role;

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
