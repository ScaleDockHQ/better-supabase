import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { schemaPreamble } from "../shared.ts";

const NAMES: ModuleNames = {
  tables: {
    subscriptions: {
      name: "chat_state_subscriptions",
      columns: {
        prefix: "key_prefix",
        thread: "thread_id",
        createdAt: "created_at",
      },
    },
    locks: {
      name: "chat_state_locks",
      columns: {
        prefix: "key_prefix",
        thread: "thread_id",
        token: "token",
        expiresAt: "expires_at",
        updatedAt: "updated_at",
      },
    },
    cache: {
      name: "chat_state_cache",
      columns: {
        prefix: "key_prefix",
        key: "cache_key",
        value: "value",
        expiresAt: "expires_at",
        updatedAt: "updated_at",
      },
    },
    lists: {
      name: "chat_state_lists",
      columns: {
        id: "id",
        prefix: "key_prefix",
        key: "list_key",
        value: "value",
        expiresAt: "expires_at",
      },
    },
    queues: {
      name: "chat_state_queues",
      columns: {
        id: "id",
        prefix: "key_prefix",
        thread: "thread_id",
        value: "value",
        expiresAt: "expires_at",
      },
    },
    installations: {
      name: "chat_installations",
      // The row outlives a tenant purge until the app revokes its credential
      // (installations.uninstallTenant in better-supabase/chat-sdk).
      lifecycle: { tenant: "tenant", purge: false, omit: ["credentialRef"] },
      columns: {
        id: "id",
        tenant: "tenant_id",
        adapter: "adapter",
        externalId: "external_id",
        credentialRef: "credential_ref",
        metadata: "metadata",
        installedBy: "installed_by",
        installedAt: "installed_at",
        uninstalledAt: "uninstalled_at",
      },
    },
  },
};

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const sub = ctx.table("subscriptions");
  const lk = ctx.table("locks");
  const ca = ctx.table("cache");
  const li = ctx.table("lists");
  const qu = ctx.table("queues");
  const ins = ctx.table("installations");
  const cs = (column: string): string => ctx.col("subscriptions", column);
  const cl = (column: string): string => ctx.col("locks", column);
  const cc = (column: string): string => ctx.col("cache", column);
  const cli = (column: string): string => ctx.col("lists", column);
  const cq = (column: string): string => ctx.col("queues", column);
  const ci = (column: string): string => ctx.col("installations", column);
  const serviceOnly = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;
  const table = (
    name: string,
  ): string => `alter table ${name} enable row level security;
revoke all on ${name} from anon, authenticated;
grant all on ${name} to service_role;`;
  const ttl = (ms: string): string =>
    `case when ${ms} is null or ${ms} <= 0 then null else now() + make_interval(secs => ${ms} / 1000.0) end`;
  const live = (column: string): string =>
    `(${column} is null or ${column} > now())`;
  const lockJson = (row: string): string =>
    `jsonb_build_object('thread_id', ${row}.${cl("thread")}, 'token', ${row}.${cl("token")}, 'expires_at', ${row}.${cl("expiresAt")})`;

  return `${schemaPreamble(ctx)}
-- The Chat SDK StateAdapter in Postgres: thread subscriptions, locks with a
-- token, a key-value cache, capped lists and per-thread message queues, each
-- under a key prefix so several bots share the tables. Only the service role
-- reads and writes; better-supabase/chat-sdk's createSupabaseState() calls
-- these functions. Expired rows read as missing; purge_chat_state() deletes
-- them, e.g. from pg_cron:
--   select cron.schedule('purge-chat-state', '*/15 * * * *', 'select ${fn("purge_chat_state")}()');
create table if not exists ${sub} (
  ${cs("prefix")} text not null,
  ${cs("thread")} text not null,
  ${cs("createdAt")} timestamptz not null default now(),
  primary key (${cs("prefix")}, ${cs("thread")})
);
${table(sub)}

create table if not exists ${lk} (
  ${cl("prefix")} text not null,
  ${cl("thread")} text not null,
  ${cl("token")} text not null,
  ${cl("expiresAt")} timestamptz not null,
  ${cl("updatedAt")} timestamptz not null default now(),
  primary key (${cl("prefix")}, ${cl("thread")})
);
create index if not exists chat_state_locks_expires_idx on ${lk} (${cl("expiresAt")});
${table(lk)}

create table if not exists ${ca} (
  ${cc("prefix")} text not null,
  ${cc("key")} text not null,
  ${cc("value")} jsonb not null,
  ${cc("expiresAt")} timestamptz,
  ${cc("updatedAt")} timestamptz not null default now(),
  primary key (${cc("prefix")}, ${cc("key")})
);
create index if not exists chat_state_cache_expires_idx on ${ca} (${cc("expiresAt")}) where ${cc("expiresAt")} is not null;
${table(ca)}

create table if not exists ${li} (
  ${cli("id")} bigint generated always as identity primary key,
  ${cli("prefix")} text not null,
  ${cli("key")} text not null,
  ${cli("value")} jsonb not null,
  ${cli("expiresAt")} timestamptz
);
create index if not exists chat_state_lists_key_idx on ${li} (${cli("prefix")}, ${cli("key")}, ${cli("id")});
create index if not exists chat_state_lists_expires_idx on ${li} (${cli("expiresAt")}) where ${cli("expiresAt")} is not null;
${table(li)}

create table if not exists ${qu} (
  ${cq("id")} bigint generated always as identity primary key,
  ${cq("prefix")} text not null,
  ${cq("thread")} text not null,
  ${cq("value")} jsonb not null,
  ${cq("expiresAt")} timestamptz not null
);
create index if not exists chat_state_queues_thread_idx on ${qu} (${cq("prefix")}, ${cq("thread")}, ${cq("id")});
create index if not exists chat_state_queues_expires_idx on ${qu} (${cq("expiresAt")});
${table(qu)}

-- A workspace (a Slack team, a GitHub installation, a WhatsApp number) that
-- installed a bot. credential_ref names its token in a CredentialProvider;
-- the token itself never lands here. Uninstalling keeps the row, so a
-- reinstall finds its tenant, and the app revokes the credential.
create table if not exists ${ins} (
  ${ci("id")} uuid primary key default gen_random_uuid(),
  ${ci("tenant")} ${id},
  ${ci("adapter")} text not null check (length(${ci("adapter")}) between 1 and 100),
  ${ci("externalId")} text not null check (length(${ci("externalId")}) between 1 and 500),
  ${ci("credentialRef")} jsonb check (${ci("credentialRef")} is null or (jsonb_typeof(${ci("credentialRef")}) = 'object' and ${ci("credentialRef")} ? 'provider')),
  ${ci("metadata")} jsonb not null default '{}'::jsonb,
  ${ci("installedBy")} uuid references auth.users (id) on delete set null,
  ${ci("installedAt")} timestamptz not null default now(),
  ${ci("uninstalledAt")} timestamptz,
  unique (${ci("adapter")}, ${ci("externalId")})
);
create index if not exists chat_installations_tenant_idx on ${ins} (${ci("tenant")});
${table(ins)}

create or replace function ${fn("chat_state_subscribe")}(prefix text, thread_id text)
returns void
language sql
set search_path = ''
as $$
  insert into ${sub} (${cs("prefix")}, ${cs("thread")}) values (prefix, thread_id)
  on conflict do nothing;
$$;
${serviceOnly(`${fn("chat_state_subscribe")}(text, text)`)}

create or replace function ${fn("chat_state_unsubscribe")}(prefix text, thread_id text)
returns void
language sql
set search_path = ''
as $$
  delete from ${sub} s where s.${cs("prefix")} = chat_state_unsubscribe.prefix and s.${cs("thread")} = chat_state_unsubscribe.thread_id;
$$;
${serviceOnly(`${fn("chat_state_unsubscribe")}(text, text)`)}

create or replace function ${fn("chat_state_is_subscribed")}(prefix text, thread_id text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from ${sub} s where s.${cs("prefix")} = chat_state_is_subscribed.prefix and s.${cs("thread")} = chat_state_is_subscribed.thread_id);
$$;
${serviceOnly(`${fn("chat_state_is_subscribed")}(text, text)`)}

-- Takes the thread's lock when it is free or expired: { thread_id, token,
-- expires_at }, or null while another holder's lock is live.
create or replace function ${fn("chat_state_acquire_lock")}(prefix text, thread_id text, token text, ttl_ms integer)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_lock ${lk}%rowtype;
begin
  insert into ${lk} as l (${cl("prefix")}, ${cl("thread")}, ${cl("token")}, ${cl("expiresAt")})
  values (prefix, thread_id, token, now() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0))
  on conflict (${cl("prefix")}, ${cl("thread")}) do update
    set ${cl("token")} = excluded.${cl("token")}, ${cl("expiresAt")} = excluded.${cl("expiresAt")}, ${cl("updatedAt")} = now()
    where l.${cl("expiresAt")} <= now()
  returning * into v_lock;
  if not found then
    return null;
  end if;
  return ${lockJson("v_lock")};
end;
$$;
${serviceOnly(`${fn("chat_state_acquire_lock")}(text, text, text, integer)`)}

-- Extends a live lock the token still holds; an expired lock stays expired.
create or replace function ${fn("chat_state_extend_lock")}(prefix text, thread_id text, token text, ttl_ms integer)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  update ${lk} l
  set ${cl("expiresAt")} = now() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0), ${cl("updatedAt")} = now()
  where l.${cl("prefix")} = chat_state_extend_lock.prefix
    and l.${cl("thread")} = chat_state_extend_lock.thread_id
    and l.${cl("token")} = chat_state_extend_lock.token
    and l.${cl("expiresAt")} > now();
  return found;
end;
$$;
${serviceOnly(`${fn("chat_state_extend_lock")}(text, text, text, integer)`)}

create or replace function ${fn("chat_state_release_lock")}(prefix text, thread_id text, token text)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  delete from ${lk} l
  where l.${cl("prefix")} = chat_state_release_lock.prefix
    and l.${cl("thread")} = chat_state_release_lock.thread_id
    and l.${cl("token")} = chat_state_release_lock.token;
  return found;
end;
$$;
${serviceOnly(`${fn("chat_state_release_lock")}(text, text, text)`)}

create or replace function ${fn("chat_state_force_release_lock")}(prefix text, thread_id text)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  delete from ${lk} l
  where l.${cl("prefix")} = chat_state_force_release_lock.prefix
    and l.${cl("thread")} = chat_state_force_release_lock.thread_id;
  return found;
end;
$$;
${serviceOnly(`${fn("chat_state_force_release_lock")}(text, text)`)}

-- { value } for a live key, or null, so a stored JSON null stays apart from
-- a missing key.
create or replace function ${fn("chat_state_get")}(prefix text, key text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('value', c.${cc("value")})
  from ${ca} c
  where c.${cc("prefix")} = chat_state_get.prefix and c.${cc("key")} = chat_state_get.key
    and ${live(`c.${cc("expiresAt")}`)};
$$;
${serviceOnly(`${fn("chat_state_get")}(text, text)`)}

create or replace function ${fn("chat_state_set")}(prefix text, key text, value jsonb, ttl_ms integer default null)
returns void
language sql
set search_path = ''
as $$
  insert into ${ca} (${cc("prefix")}, ${cc("key")}, ${cc("value")}, ${cc("expiresAt")})
  values (prefix, key, value, ${ttl("ttl_ms")})
  on conflict (${cc("prefix")}, ${cc("key")}) do update
    set ${cc("value")} = excluded.${cc("value")}, ${cc("expiresAt")} = excluded.${cc("expiresAt")}, ${cc("updatedAt")} = now();
$$;
${serviceOnly(`${fn("chat_state_set")}(text, text, jsonb, integer)`)}

-- Writes the key unless a live value holds it; true when it wrote.
create or replace function ${fn("chat_state_set_if_not_exists")}(prefix text, key text, value jsonb, ttl_ms integer default null)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into ${ca} as c (${cc("prefix")}, ${cc("key")}, ${cc("value")}, ${cc("expiresAt")})
  values (prefix, key, value, ${ttl("ttl_ms")})
  on conflict (${cc("prefix")}, ${cc("key")}) do update
    set ${cc("value")} = excluded.${cc("value")}, ${cc("expiresAt")} = excluded.${cc("expiresAt")}, ${cc("updatedAt")} = now()
    where c.${cc("expiresAt")} is not null and c.${cc("expiresAt")} <= now();
  return found;
end;
$$;
${serviceOnly(`${fn("chat_state_set_if_not_exists")}(text, text, jsonb, integer)`)}

create or replace function ${fn("chat_state_delete")}(prefix text, key text)
returns void
language sql
set search_path = ''
as $$
  delete from ${ca} c where c.${cc("prefix")} = chat_state_delete.prefix and c.${cc("key")} = chat_state_delete.key;
$$;
${serviceOnly(`${fn("chat_state_delete")}(text, text)`)}

-- Appends to the list, keeps the newest max_length entries and moves the
-- whole list's expiry to ttl_ms from now.
create or replace function ${fn("chat_state_append_to_list")}(prefix text, key text, value jsonb, max_length integer default null, ttl_ms integer default null)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_expires timestamptz := ${ttl("ttl_ms")};
begin
  insert into ${li} (${cli("prefix")}, ${cli("key")}, ${cli("value")}, ${cli("expiresAt")})
  values (prefix, key, value, v_expires);
  if max_length is not null and max_length > 0 then
    delete from ${li} l
    where l.${cli("prefix")} = chat_state_append_to_list.prefix and l.${cli("key")} = chat_state_append_to_list.key
      and l.${cli("id")} < (
        select k.${cli("id")} from ${li} k
        where k.${cli("prefix")} = chat_state_append_to_list.prefix and k.${cli("key")} = chat_state_append_to_list.key
        order by k.${cli("id")} desc
        offset max_length - 1 limit 1
      );
  end if;
  update ${li} l set ${cli("expiresAt")} = v_expires
  where l.${cli("prefix")} = chat_state_append_to_list.prefix and l.${cli("key")} = chat_state_append_to_list.key
    and l.${cli("expiresAt")} is distinct from v_expires;
end;
$$;
${serviceOnly(`${fn("chat_state_append_to_list")}(text, text, jsonb, integer, integer)`)}

create or replace function ${fn("chat_state_get_list")}(prefix text, key text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(l.${cli("value")} order by l.${cli("id")}), '[]'::jsonb)
  from ${li} l
  where l.${cli("prefix")} = chat_state_get_list.prefix and l.${cli("key")} = chat_state_get_list.key
    and ${live(`l.${cli("expiresAt")}`)};
$$;
${serviceOnly(`${fn("chat_state_get_list")}(text, text)`)}

-- Queues an entry for a busy thread, keeps the newest max_size live entries
-- and returns the depth after the insert.
create or replace function ${fn("chat_state_enqueue")}(prefix text, thread_id text, entry jsonb, expires_at timestamptz, max_size integer default null)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_depth integer;
begin
  delete from ${qu} q
  where q.${cq("prefix")} = chat_state_enqueue.prefix and q.${cq("thread")} = chat_state_enqueue.thread_id
    and q.${cq("expiresAt")} <= now();
  insert into ${qu} (${cq("prefix")}, ${cq("thread")}, ${cq("value")}, ${cq("expiresAt")})
  values (prefix, thread_id, entry, expires_at);
  if max_size is not null and max_size > 0 then
    delete from ${qu} q
    where q.${cq("prefix")} = chat_state_enqueue.prefix and q.${cq("thread")} = chat_state_enqueue.thread_id
      and q.${cq("id")} < (
        select k.${cq("id")} from ${qu} k
        where k.${cq("prefix")} = chat_state_enqueue.prefix and k.${cq("thread")} = chat_state_enqueue.thread_id
        order by k.${cq("id")} desc
        offset max_size - 1 limit 1
      );
  end if;
  select count(*)::integer into v_depth from ${qu} q
  where q.${cq("prefix")} = chat_state_enqueue.prefix and q.${cq("thread")} = chat_state_enqueue.thread_id
    and q.${cq("expiresAt")} > now();
  return v_depth;
end;
$$;
${serviceOnly(`${fn("chat_state_enqueue")}(text, text, jsonb, timestamptz, integer)`)}

-- Removes and returns the oldest live entry, or null. Concurrent workers
-- skip an entry another one is taking.
create or replace function ${fn("chat_state_dequeue")}(prefix text, thread_id text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_value jsonb;
begin
  delete from ${qu} q
  where q.${cq("prefix")} = chat_state_dequeue.prefix and q.${cq("thread")} = chat_state_dequeue.thread_id
    and q.${cq("expiresAt")} <= now();
  delete from ${qu} q
  where q.${cq("id")} = (
    select k.${cq("id")} from ${qu} k
    where k.${cq("prefix")} = chat_state_dequeue.prefix and k.${cq("thread")} = chat_state_dequeue.thread_id
    order by k.${cq("id")}
    limit 1
    for update skip locked
  )
  returning q.${cq("value")} into v_value;
  return v_value;
end;
$$;
${serviceOnly(`${fn("chat_state_dequeue")}(text, text)`)}

create or replace function ${fn("chat_state_queue_depth")}(prefix text, thread_id text)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(*)::integer from ${qu} q
  where q.${cq("prefix")} = chat_state_queue_depth.prefix and q.${cq("thread")} = chat_state_queue_depth.thread_id
    and q.${cq("expiresAt")} > now();
$$;
${serviceOnly(`${fn("chat_state_queue_depth")}(text, text)`)}

-- Deletes expired locks, cache keys, list entries and queued messages, at
-- most batch of each per call; returns how many rows went.
create or replace function ${fn("purge_chat_state")}(batch integer default 5000)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_limit integer := greatest(coalesce(batch, 5000), 1);
  v_count integer := 0;
  v_rows integer;
begin
  delete from ${lk} l where ctid in (select ctid from ${lk} where ${cl("expiresAt")} <= now() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from ${ca} c where ctid in (select ctid from ${ca} where ${cc("expiresAt")} <= now() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from ${li} l where l.${cli("id")} in (select ${cli("id")} from ${li} where ${cli("expiresAt")} <= now() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from ${qu} q where q.${cq("id")} in (select ${cq("id")} from ${qu} where ${cq("expiresAt")} <= now() limit v_limit);
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
${serviceOnly(`${fn("purge_chat_state")}(integer)`)}

-- Records an install, or a reinstall of an uninstalled workspace, and
-- returns the row. A reinstall replaces the credential_ref; the caller
-- revokes the old one it gets back as previous_credential_ref.
create or replace function ${fn("chat_install")}(adapter text, external_id text, tenant ${id} default null, credential_ref jsonb default null, installed_by uuid default null, metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_previous jsonb;
  v_row ${ins}%rowtype;
begin
  select ${ci("credentialRef")} into v_previous from ${ins}
  where ${ci("adapter")} = chat_install.adapter and ${ci("externalId")} = chat_install.external_id
  for update;
  insert into ${ins} as i (${ci("tenant")}, ${ci("adapter")}, ${ci("externalId")}, ${ci("credentialRef")}, ${ci("installedBy")}, ${ci("metadata")})
  values (tenant, adapter, external_id, credential_ref, installed_by, coalesce(metadata, '{}'::jsonb))
  on conflict (${ci("adapter")}, ${ci("externalId")}) do update
    set ${ci("tenant")} = coalesce(excluded.${ci("tenant")}, i.${ci("tenant")}),
        ${ci("credentialRef")} = excluded.${ci("credentialRef")},
        ${ci("installedBy")} = coalesce(excluded.${ci("installedBy")}, i.${ci("installedBy")}),
        ${ci("metadata")} = i.${ci("metadata")} || excluded.${ci("metadata")},
        ${ci("installedAt")} = now(),
        ${ci("uninstalledAt")} = null
  returning * into v_row;
  return to_jsonb(v_row) || jsonb_build_object(
    'previous_credential_ref',
    case when v_previous is distinct from v_row.${ci("credentialRef")} then v_previous end
  );
end;
$$;
${serviceOnly(`${fn("chat_install")}(text, text, ${id}, jsonb, uuid, jsonb)`)}

create or replace function ${fn("chat_installation")}(adapter text, external_id text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(i) from ${ins} i
  where i.${ci("adapter")} = chat_installation.adapter and i.${ci("externalId")} = chat_installation.external_id;
$$;
${serviceOnly(`${fn("chat_installation")}(text, text)`)}

create or replace function ${fn("list_chat_installations")}(tenant ${id} default null, adapter text default null, include_uninstalled boolean default false)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(i) order by i.${ci("installedAt")} desc), '[]'::jsonb)
  from ${ins} i
  where (list_chat_installations.tenant is null or i.${ci("tenant")} = list_chat_installations.tenant)
    and (list_chat_installations.adapter is null or i.${ci("adapter")} = list_chat_installations.adapter)
    and (coalesce(include_uninstalled, false) or i.${ci("uninstalledAt")} is null);
$$;
${serviceOnly(`${fn("list_chat_installations")}(${id}, text, boolean)`)}

-- Marks the install removed, clears its credential_ref and returns the row
-- with the ref it held, so the caller revokes the credential. Null when
-- there was no live install.
create or replace function ${fn("chat_uninstall")}(adapter text, external_id text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_ref jsonb;
  v_row ${ins}%rowtype;
begin
  select i.${ci("credentialRef")} into v_ref from ${ins} i
  where i.${ci("adapter")} = chat_uninstall.adapter and i.${ci("externalId")} = chat_uninstall.external_id
    and i.${ci("uninstalledAt")} is null
  for update;
  if not found then
    return null;
  end if;
  update ${ins} i set ${ci("uninstalledAt")} = now(), ${ci("credentialRef")} = null
  where i.${ci("adapter")} = chat_uninstall.adapter and i.${ci("externalId")} = chat_uninstall.external_id
  returning * into v_row;
  return to_jsonb(v_row) || jsonb_build_object('previous_credential_ref', v_ref);
end;
$$;
${serviceOnly(`${fn("chat_uninstall")}(text, text)`)}`;
}

function contract(): readonly ModuleContractFunction[] {
  const pair = ["text", "text"] as const;
  return [
    { name: "chat_state_subscribe", args: pair, returns: "void" },
    { name: "chat_state_unsubscribe", args: pair, returns: "void" },
    { name: "chat_state_is_subscribed", args: pair, returns: "boolean" },
    {
      name: "chat_state_acquire_lock",
      args: ["text", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "chat_state_extend_lock",
      args: ["text", "text", "text", "integer"],
      returns: "boolean",
    },
    {
      name: "chat_state_release_lock",
      args: ["text", "text", "text"],
      returns: "boolean",
    },
    { name: "chat_state_force_release_lock", args: pair, returns: "boolean" },
    { name: "chat_state_get", args: pair, returns: "jsonb" },
    {
      name: "chat_state_set",
      args: ["text", "text", "jsonb", "integer"],
      returns: "void",
    },
    {
      name: "chat_state_set_if_not_exists",
      args: ["text", "text", "jsonb", "integer"],
      returns: "boolean",
    },
    { name: "chat_state_delete", args: pair, returns: "void" },
    {
      name: "chat_state_append_to_list",
      args: ["text", "text", "jsonb", "integer", "integer"],
      returns: "void",
    },
    { name: "chat_state_get_list", args: pair, returns: "jsonb" },
    {
      name: "chat_state_enqueue",
      args: ["text", "text", "jsonb", "timestamptz", "integer"],
      returns: "integer",
    },
    { name: "chat_state_dequeue", args: pair, returns: "jsonb" },
    { name: "chat_state_queue_depth", args: pair, returns: "integer" },
    { name: "purge_chat_state", args: ["integer"], returns: "integer" },
    {
      name: "chat_install",
      args: ["text", "text", "{id}", "jsonb", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "chat_installation", args: pair, returns: "jsonb" },
    {
      name: "list_chat_installations",
      args: ["{id}", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "chat_uninstall", args: pair, returns: "jsonb" },
  ];
}

export const CHAT_SDK_STATE: ModuleDefinition = {
  name: "chat-sdk-state",
  title: "Chat SDK state",
  description:
    "The Chat SDK StateAdapter in Postgres for better-supabase/chat-sdk: thread subscriptions, token locks, a TTL cache, capped lists and per-thread queues under a key prefix, plus the bot installations per workspace with a credential_ref instead of the token. Service role only.",
  requires: [],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
