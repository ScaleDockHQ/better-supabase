-- better-supabase module: ai-providers (0.5.1)
-- @bs-module ai-providers@1 managed
-- A tenant's own provider keys as credential_ref rows, a registry of provider batch jobs with their results and a poll claim, and a registry of sandboxes and containers with an idle-stop claim.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- A tenant's own provider keys (BYOK). credential_ref names the key in a
-- CredentialProvider, such as Vault; the key itself is never stored here.
-- settings holds the provider's other options (a region, a project id) and
-- must not hold secrets.
create table if not exists "better_supabase"."ai_provider_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "provider" text not null check ("provider" ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  "name" text not null default 'default' check (length("name") between 1 and 100),
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "settings" jsonb not null default '{}' check (jsonb_typeof("settings") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("organization_id", "provider", "name")
);
create index if not exists ai_provider_keys_created_by_idx on "better_supabase"."ai_provider_keys" ("created_by");
alter table "better_supabase"."ai_provider_keys" enable row level security;
revoke all on "better_supabase"."ai_provider_keys" from anon, authenticated;
grant select on "better_supabase"."ai_provider_keys" to authenticated;
grant all on "better_supabase"."ai_provider_keys" to service_role;
drop policy if exists ai_provider_keys_read on "better_supabase"."ai_provider_keys";
create policy ai_provider_keys_read on "better_supabase"."ai_provider_keys" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')));

-- Batch jobs started with a provider's batch API, polled until they finish.
-- reference is the SDK's batch reference ({ version, id, provider }).
create table if not exists "better_supabase"."ai_batches" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "provider" text not null check (length("provider") between 1 and 100),
  "reference" jsonb not null check (jsonb_typeof("reference") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'completed', 'failed', 'cancelled')),
  "raw_status" text check (length("raw_status") <= 100),
  "item_count" integer not null default 0 check ("item_count" >= 0),
  "counts" jsonb not null default '{}' check (jsonb_typeof("counts") = 'object'),
  "error" text check (length("error") <= 4000),
  "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object'),
  "results_saved" boolean not null default false,
  "polls" integer not null default 0,
  "next_poll_at" timestamptz default now(),
  "expires_at" timestamptz,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists ai_batches_due_idx on "better_supabase"."ai_batches" ("next_poll_at") where "status" = 'pending' or not "results_saved";
create index if not exists ai_batches_tenant_idx on "better_supabase"."ai_batches" ("organization_id", "created_at" desc);
create index if not exists ai_batches_user_idx on "better_supabase"."ai_batches" ("user_id");
alter table "better_supabase"."ai_batches" enable row level security;
revoke all on "better_supabase"."ai_batches" from anon, authenticated;
grant select on "better_supabase"."ai_batches" to authenticated;
grant all on "better_supabase"."ai_batches" to service_role;
drop policy if exists ai_batches_read on "better_supabase"."ai_batches";
create policy ai_batches_read on "better_supabase"."ai_batches" for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')));

create table if not exists "better_supabase"."ai_batch_items" (
  "batch_id" uuid not null references "better_supabase"."ai_batches" ("id") on delete cascade,
  "request_id" text not null check (length("request_id") between 1 and 200),
  "organization_id" uuid not null,
  "status" text not null check ("status" in ('succeeded', 'failed', 'cancelled', 'expired')),
  "output" jsonb,
  "usage" jsonb,
  "error" text check (length("error") <= 4000),
  "created_at" timestamptz not null default now(),
  primary key ("batch_id", "request_id")
);
create index if not exists ai_batch_items_tenant_idx on "better_supabase"."ai_batch_items" ("organization_id");
alter table "better_supabase"."ai_batch_items" enable row level security;
revoke all on "better_supabase"."ai_batch_items" from anon, authenticated;
grant select on "better_supabase"."ai_batch_items" to authenticated;
grant all on "better_supabase"."ai_batch_items" to service_role;
drop policy if exists ai_batch_items_read on "better_supabase"."ai_batch_items";
create policy ai_batch_items_read on "better_supabase"."ai_batch_items" for select to authenticated
  using (exists (select 1 from "better_supabase"."ai_batches" y where y."id" = "batch_id"));

-- Sandboxes and provider containers a chat started, so an idle-stop job can
-- stop the ones nobody used for idle_seconds or past expires_at.
create table if not exists "better_supabase"."ai_sandboxes" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "provider" text not null check ("provider" ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  "sandbox_id" text not null check (length("sandbox_id") between 1 and 200),
  "container_id" text check (length("container_id") <= 200),
  "status" text not null default 'running' check ("status" in ('running', 'stopping', 'stopped')),
  "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object'),
  "idle_seconds" integer not null default 600 check ("idle_seconds" > 0),
  "error" text check (length("error") <= 4000),
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz,
  "stopped_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("provider", "sandbox_id")
);
create index if not exists ai_sandboxes_open_idx on "better_supabase"."ai_sandboxes" ("last_used_at") where "status" <> 'stopped';
create index if not exists ai_sandboxes_chat_idx on "better_supabase"."ai_sandboxes" ("chat_id");
create index if not exists ai_sandboxes_tenant_idx on "better_supabase"."ai_sandboxes" ("organization_id");
create index if not exists ai_sandboxes_user_idx on "better_supabase"."ai_sandboxes" ("user_id");
alter table "better_supabase"."ai_sandboxes" enable row level security;
revoke all on "better_supabase"."ai_sandboxes" from anon, authenticated;
grant select on "better_supabase"."ai_sandboxes" to authenticated;
grant all on "better_supabase"."ai_sandboxes" to service_role;
drop policy if exists ai_sandboxes_read on "better_supabase"."ai_sandboxes";
create policy ai_sandboxes_read on "better_supabase"."ai_sandboxes" for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')));

create or replace function "better_supabase"."list_ai_provider_keys"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."provider", x."name"), '[]')
  from "better_supabase"."ai_provider_keys" x where x."organization_id" = list_ai_provider_keys.tenant
$$;
revoke execute on function "better_supabase"."list_ai_provider_keys"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_provider_keys"(uuid) to authenticated, service_role;

-- Adds or replaces a tenant's key for a provider ('ai_chat.admin' or the service
-- role). Returns the key and the credential_ref it replaced, which the caller
-- revokes when it differs.
create or replace function "better_supabase"."save_ai_provider_key"(tenant uuid, provider text, credential_ref jsonb, name text default 'default', settings jsonb default '{}', enabled boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old jsonb;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage provider keys here' using errcode = '42501', hint = 'AI_PROVIDER_KEY_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_ai_provider_key.credential_ref is not null and jsonb_typeof(save_ai_provider_key.credential_ref) <> 'null'
    and (jsonb_typeof(save_ai_provider_key.credential_ref -> 'tenant') is distinct from 'string' or (save_ai_provider_key.credential_ref ->> 'tenant') is distinct from (save_ai_provider_key.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_ai_provider_key.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  select x."credential_ref" into v_old from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = save_ai_provider_key.tenant and x."provider" = save_ai_provider_key.provider and x."name" = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into "better_supabase"."ai_provider_keys" ("organization_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("organization_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
end;
$$;
revoke execute on function "better_supabase"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) to authenticated, service_role;

-- Deletes a key ('ai_chat.admin' or the service role) and returns it, so the caller
-- revokes its credential; null when there is no such key.
create or replace function "better_supabase"."delete_ai_provider_key"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_provider_keys" x where x."id" = delete_ai_provider_key.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_provider_keys" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_ai_provider_key"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_provider_key"(uuid) to authenticated, service_role;

-- Deletes every key of a tenant and returns them (service role), for the
-- step that revokes their credentials when a tenant is deleted.
create or replace function "better_supabase"."delete_ai_provider_keys"(tenant uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with gone as (
    delete from "better_supabase"."ai_provider_keys" x where x."organization_id" = delete_ai_provider_keys.tenant returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', gone."id", 'organization_id', gone."organization_id", 'provider', gone."provider", 'name', gone."name", 'credential_ref', gone."credential_ref", 'settings', gone."settings", 'enabled', gone."enabled", 'created_by', gone."created_by", 'created_at', gone."created_at", 'updated_at', gone."updated_at")), '[]') from gone
$$;
revoke execute on function "better_supabase"."delete_ai_provider_keys"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_ai_provider_keys"(uuid) to service_role;

-- The enabled keys of a tenant, for the request that resolves them (service role).
create or replace function "better_supabase"."ai_provider_keys_for"(tenant uuid, providers text[] default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."provider", x."name"), '[]')
  from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = ai_provider_keys_for.tenant and x."enabled"
    and (ai_provider_keys_for.providers is null or x."provider" = any (ai_provider_keys_for.providers))
$$;
revoke execute on function "better_supabase"."ai_provider_keys_for"(uuid, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_provider_keys_for"(uuid, text[]) to service_role;

-- Records a started batch ('ai_chat.create' or the service role). fields: user_id
-- (service role only), item_count, metadata, status, raw_status, counts,
-- expires_at.
create or replace function "better_supabase"."record_ai_batch"(tenant uuid, provider text, reference jsonb, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(record_ai_batch.fields, '{}');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', record_ai_batch.tenant, 'ai_chat.create'), false))) then
    raise exception 'you may not start batches here' using errcode = '42501', hint = 'AI_BATCH_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_batches" ("organization_id", "user_id", "provider", "reference", "status", "raw_status", "item_count", "counts", "metadata", "expires_at", "next_poll_at")
  values (
    record_ai_batch.tenant,
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (v_fields ->> 'user_id')::uuid else auth.uid() end,
    record_ai_batch.provider,
    record_ai_batch.reference,
    coalesce(v_fields ->> 'status', 'pending'),
    v_fields ->> 'raw_status',
    coalesce((v_fields ->> 'item_count')::integer, 0),
    coalesce(v_fields -> 'counts', '{}'),
    coalesce(v_fields -> 'metadata', '{}'),
    (v_fields ->> 'expires_at')::timestamptz,
    now() + interval '60 seconds'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_ai_batch"(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_ai_batch"(uuid, text, jsonb, jsonb) to authenticated, service_role;

-- Writes what a poll learned (service role). fields: status, raw_status,
-- counts, error, expires_at, results_saved, next_poll_at.
create or replace function "better_supabase"."update_ai_batch"(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(update_ai_batch.fields, '{}');
begin
  update "better_supabase"."ai_batches" x set
    "status" = coalesce(v_fields ->> 'status', x."status"),
    "raw_status" = coalesce(v_fields ->> 'raw_status', x."raw_status"),
    "counts" = coalesce(v_fields -> 'counts', x."counts"),
    "error" = case when v_fields ? 'error' then left(v_fields ->> 'error', 4000) else x."error" end,
    "expires_at" = coalesce((v_fields ->> 'expires_at')::timestamptz, x."expires_at"),
    "results_saved" = coalesce((v_fields ->> 'results_saved')::boolean, x."results_saved"),
    "next_poll_at" = case when v_fields ? 'next_poll_at' then (v_fields ->> 'next_poll_at')::timestamptz else x."next_poll_at" end,
    "completed_at" = case when coalesce(v_fields ->> 'status', x."status") <> 'pending' then coalesce(x."completed_at", now()) else null end,
    "updated_at" = now()
  where x."id" = update_ai_batch.id
  returning * into v_row;
  if not found then
    raise exception 'batch % not found', update_ai_batch.id using errcode = 'P0002', hint = 'AI_BATCH_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_ai_batch"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."update_ai_batch"(uuid, jsonb) to service_role;

-- Claims batches to poll (service role): pending ones, and finished ones
-- whose results aren't saved yet. Each claim pushes next_poll_at out by
-- lease_seconds, so two pollers don't take the same batch.
create or replace function "better_supabase"."due_ai_batches"(batch integer default 20, lease_seconds integer default 300)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_batches" y
    where (y."status" = 'pending' or not y."results_saved") and y."next_poll_at" <= now()
    order by y."next_poll_at"
    limit least(greatest(due_ai_batches.batch, 1), 200)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_batches" x set
      "polls" = x."polls" + 1,
      "next_poll_at" = now() + make_interval(secs => greatest(due_ai_batches.lease_seconds, 1)),
      "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'provider', claimed."provider", 'reference', claimed."reference", 'status', claimed."status", 'raw_status', claimed."raw_status", 'item_count', claimed."item_count", 'counts', claimed."counts", 'error', claimed."error", 'metadata', claimed."metadata", 'results_saved', claimed."results_saved", 'polls', claimed."polls", 'next_poll_at', claimed."next_poll_at", 'expires_at', claimed."expires_at", 'completed_at', claimed."completed_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."due_ai_batches"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."due_ai_batches"(integer, integer) to service_role;

-- Saves result items: { "items": [{ "request_id", "status", "output",
-- "usage", "error" }] } (service role). Returns how many were written.
create or replace function "better_supabase"."save_ai_batch_items"(id uuid, items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_items jsonb := case when jsonb_typeof(save_ai_batch_items.items) = 'object' then save_ai_batch_items.items -> 'items' else save_ai_batch_items.items end;
  v_count integer;
begin
  select x."organization_id" into v_tenant from "better_supabase"."ai_batches" x where x."id" = save_ai_batch_items.id;
  if not found then
    raise exception 'batch % not found', save_ai_batch_items.id using errcode = 'P0002', hint = 'AI_BATCH_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_batch_items" ("batch_id", "request_id", "organization_id", "status", "output", "usage", "error")
  select save_ai_batch_items.id, item ->> 'request_id', v_tenant, item ->> 'status', item -> 'output', item -> 'usage', left(item ->> 'error', 4000)
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  on conflict ("batch_id", "request_id") do update set
    "status" = excluded."status",
    "output" = excluded."output",
    "usage" = excluded."usage",
    "error" = excluded."error";
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."save_ai_batch_items"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."save_ai_batch_items"(uuid, jsonb) to service_role;

create or replace function "better_supabase"."get_ai_batch"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_batches" x where x."id" = get_ai_batch.id
$$;
revoke execute on function "better_supabase"."get_ai_batch"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_batch"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_ai_batches"(tenant uuid, status text default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."ai_batches" y
    where y."organization_id" = list_ai_batches.tenant and (list_ai_batches.status is null or y."status" = list_ai_batches.status)
    order by y."created_at" desc
    limit least(greatest(list_ai_batches.max_rows, 1), 200)
  ) x
$$;
revoke execute on function "better_supabase"."list_ai_batches"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_batches"(uuid, text, integer) to authenticated, service_role;

-- A page of a batch's results, after request_id after.
create or replace function "better_supabase"."list_ai_batch_items"(id uuid, after text default null, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', x."batch_id", 'request_id', x."request_id", 'organization_id', x."organization_id", 'status', x."status", 'output', x."output", 'usage', x."usage", 'error', x."error", 'created_at', x."created_at") order by x."request_id"), '[]')
  from (
    select * from "better_supabase"."ai_batch_items" y
    where y."batch_id" = list_ai_batch_items.id and (list_ai_batch_items.after is null or y."request_id" > list_ai_batch_items.after)
    order by y."request_id"
    limit least(greatest(list_ai_batch_items.max_rows, 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_ai_batch_items"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_batch_items"(uuid, text, integer) to authenticated, service_role;

-- Records a sandbox or container the app started, or marks a known one used
-- (service role). fields: user_id, chat_id, container_id, metadata,
-- idle_seconds, expires_at.
create or replace function "better_supabase"."register_ai_sandbox"(tenant uuid, provider text, sandbox_id text, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_sandboxes"%rowtype;
  v_fields jsonb := coalesce(register_ai_sandbox.fields, '{}');
begin
  insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "provider", "sandbox_id", "container_id", "metadata", "idle_seconds", "expires_at")
  values (
    register_ai_sandbox.tenant,
    (v_fields ->> 'user_id')::uuid,
    (v_fields ->> 'chat_id')::uuid,
    register_ai_sandbox.provider,
    register_ai_sandbox.sandbox_id,
    v_fields ->> 'container_id',
    coalesce(v_fields -> 'metadata', '{}'),
    coalesce((v_fields ->> 'idle_seconds')::integer, 600),
    (v_fields ->> 'expires_at')::timestamptz
  )
  on conflict ("provider", "sandbox_id") do update set
    "container_id" = coalesce(excluded."container_id", cur."container_id"),
    "chat_id" = coalesce(excluded."chat_id", cur."chat_id"),
    "metadata" = cur."metadata" || excluded."metadata",
    "idle_seconds" = excluded."idle_seconds",
    "expires_at" = coalesce(excluded."expires_at", cur."expires_at"),
    "status" = 'running',
    "error" = null,
    "stopped_at" = null,
    "last_used_at" = now(),
    "updated_at" = now()
  where cur."organization_id" = excluded."organization_id"
  returning * into v_row;
  if not found then
    raise exception 'sandbox % belongs to another tenant', register_ai_sandbox.sandbox_id using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'provider', v_row."provider", 'sandbox_id', v_row."sandbox_id", 'container_id', v_row."container_id", 'status', v_row."status", 'metadata', v_row."metadata", 'idle_seconds', v_row."idle_seconds", 'error', v_row."error", 'last_used_at', v_row."last_used_at", 'expires_at', v_row."expires_at", 'stopped_at', v_row."stopped_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_ai_sandbox"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."register_ai_sandbox"(uuid, text, text, jsonb) to service_role;

-- Marks a sandbox used now (service role); false when it is not running.
create or replace function "better_supabase"."touch_ai_sandbox"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."ai_sandboxes" x set "last_used_at" = now(), "updated_at" = now()
  where x."id" = touch_ai_sandbox.id and x."status" = 'running';
  return found;
end;
$$;
revoke execute on function "better_supabase"."touch_ai_sandbox"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."touch_ai_sandbox"(uuid) to service_role;

-- The running sandbox of a chat for a provider, to reuse it (service role).
create or replace function "better_supabase"."ai_sandbox_for"(chat_id uuid, provider text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_sandboxes" x
  where x."chat_id" = ai_sandbox_for.chat_id and x."provider" = ai_sandbox_for.provider and x."status" = 'running'
    and (x."expires_at" is null or x."expires_at" > now())
  order by x."last_used_at" desc
  limit 1
$$;
revoke execute on function "better_supabase"."ai_sandbox_for"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_sandbox_for"(uuid, text) to service_role;

-- Claims sandboxes to stop (service role): running ones idle for
-- idle_seconds or past expires_at, and ones a stopper claimed more than
-- lease_seconds ago without finishing.
create or replace function "better_supabase"."idle_ai_sandboxes"(batch integer default 50, lease_seconds integer default 300)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_sandboxes" y
    where (y."status" = 'running' and (y."last_used_at" + make_interval(secs => y."idle_seconds") <= now() or y."expires_at" <= now()))
       or (y."status" = 'stopping' and y."updated_at" <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1)))
    order by y."last_used_at"
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_sandboxes" x set "status" = 'stopping', "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'chat_id', claimed."chat_id", 'provider', claimed."provider", 'sandbox_id', claimed."sandbox_id", 'container_id', claimed."container_id", 'status', claimed."status", 'metadata', claimed."metadata", 'idle_seconds', claimed."idle_seconds", 'error', claimed."error", 'last_used_at', claimed."last_used_at", 'expires_at', claimed."expires_at", 'stopped_at', claimed."stopped_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."idle_ai_sandboxes"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."idle_ai_sandboxes"(integer, integer) to service_role;

-- Finishes a stop (service role): stopped, or back to running with the
-- error so the next run tries again.
create or replace function "better_supabase"."finish_ai_sandbox_stop"(id uuid, stopped boolean, error text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."ai_sandboxes" x set
    "status" = case when finish_ai_sandbox_stop.stopped then 'stopped' else 'running' end,
    "stopped_at" = case when finish_ai_sandbox_stop.stopped then now() else null end,
    "error" = left(finish_ai_sandbox_stop.error, 4000),
    "updated_at" = now()
  where x."id" = finish_ai_sandbox_stop.id and x."status" <> 'stopped';
  return found;
end;
$$;
revoke execute on function "better_supabase"."finish_ai_sandbox_stop"(uuid, boolean, text) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_ai_sandbox_stop"(uuid, boolean, text) to service_role;

create or replace function "better_supabase"."list_ai_sandboxes"(tenant uuid, chat_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from "better_supabase"."ai_sandboxes" x
  where x."organization_id" = list_ai_sandboxes.tenant and (list_ai_sandboxes.chat_id is null or x."chat_id" = list_ai_sandboxes.chat_id)
$$;
revoke execute on function "better_supabase"."list_ai_sandboxes"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_sandboxes"(uuid, uuid) to authenticated, service_role;

-- sql.modules.ai-providers.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."list_ai_provider_keys"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_provider_keys"($1) $$;
revoke execute on function "api"."list_ai_provider_keys"(uuid) from public, anon;
grant execute on function "api"."list_ai_provider_keys"(uuid) to authenticated, service_role;

create or replace function "api"."save_ai_provider_key"(tenant uuid, provider text, credential_ref jsonb, name text default 'default', settings jsonb default '{}', enabled boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_ai_provider_key"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) from public, anon;
grant execute on function "api"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."delete_ai_provider_key"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_provider_key"($1) $$;
revoke execute on function "api"."delete_ai_provider_key"(uuid) from public, anon;
grant execute on function "api"."delete_ai_provider_key"(uuid) to authenticated, service_role;

create or replace function "api"."delete_ai_provider_keys"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_provider_keys"($1) $$;
revoke execute on function "api"."delete_ai_provider_keys"(uuid) from public, anon, authenticated;
grant execute on function "api"."delete_ai_provider_keys"(uuid) to service_role;

create or replace function "api"."ai_provider_keys_for"(tenant uuid, providers text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_provider_keys_for"($1, $2) $$;
revoke execute on function "api"."ai_provider_keys_for"(uuid, text[]) from public, anon, authenticated;
grant execute on function "api"."ai_provider_keys_for"(uuid, text[]) to service_role;

create or replace function "api"."record_ai_batch"(tenant uuid, provider text, reference jsonb, fields jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_ai_batch"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_ai_batch"(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function "api"."record_ai_batch"(uuid, text, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_ai_batch"(id uuid, fields jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_ai_batch"($1, $2) $$;
revoke execute on function "api"."update_ai_batch"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."update_ai_batch"(uuid, jsonb) to service_role;

create or replace function "api"."due_ai_batches"(batch integer default 20, lease_seconds integer default 300)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."due_ai_batches"($1, $2) $$;
revoke execute on function "api"."due_ai_batches"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."due_ai_batches"(integer, integer) to service_role;

create or replace function "api"."save_ai_batch_items"(id uuid, items jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_ai_batch_items"($1, $2) $$;
revoke execute on function "api"."save_ai_batch_items"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."save_ai_batch_items"(uuid, jsonb) to service_role;

create or replace function "api"."get_ai_batch"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_batch"($1) $$;
revoke execute on function "api"."get_ai_batch"(uuid) from public, anon;
grant execute on function "api"."get_ai_batch"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_batches"(tenant uuid, status text default null, max_rows integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_batches"($1, $2, $3) $$;
revoke execute on function "api"."list_ai_batches"(uuid, text, integer) from public, anon;
grant execute on function "api"."list_ai_batches"(uuid, text, integer) to authenticated, service_role;

create or replace function "api"."list_ai_batch_items"(id uuid, after text default null, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_batch_items"($1, $2, $3) $$;
revoke execute on function "api"."list_ai_batch_items"(uuid, text, integer) from public, anon;
grant execute on function "api"."list_ai_batch_items"(uuid, text, integer) to authenticated, service_role;

create or replace function "api"."register_ai_sandbox"(tenant uuid, provider text, sandbox_id text, fields jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_ai_sandbox"($1, $2, $3, $4) $$;
revoke execute on function "api"."register_ai_sandbox"(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function "api"."register_ai_sandbox"(uuid, text, text, jsonb) to service_role;

create or replace function "api"."touch_ai_sandbox"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."touch_ai_sandbox"($1) $$;
revoke execute on function "api"."touch_ai_sandbox"(uuid) from public, anon, authenticated;
grant execute on function "api"."touch_ai_sandbox"(uuid) to service_role;

create or replace function "api"."ai_sandbox_for"(chat_id uuid, provider text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_sandbox_for"($1, $2) $$;
revoke execute on function "api"."ai_sandbox_for"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."ai_sandbox_for"(uuid, text) to service_role;

create or replace function "api"."idle_ai_sandboxes"(batch integer default 50, lease_seconds integer default 300)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."idle_ai_sandboxes"($1, $2) $$;
revoke execute on function "api"."idle_ai_sandboxes"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."idle_ai_sandboxes"(integer, integer) to service_role;

create or replace function "api"."finish_ai_sandbox_stop"(id uuid, stopped boolean, error text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."finish_ai_sandbox_stop"($1, $2, $3) $$;
revoke execute on function "api"."finish_ai_sandbox_stop"(uuid, boolean, text) from public, anon, authenticated;
grant execute on function "api"."finish_ai_sandbox_stop"(uuid, boolean, text) to service_role;

create or replace function "api"."list_ai_sandboxes"(tenant uuid, chat_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_sandboxes"($1, $2) $$;
revoke execute on function "api"."list_ai_sandboxes"(uuid, uuid) from public, anon;
grant execute on function "api"."list_ai_sandboxes"(uuid, uuid) to authenticated, service_role;

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
