-- better-supabase module: ai-cache (0.5.1)
-- @bs-module ai-cache@1 managed
-- Model responses cached by a key the application derives from the request, with a TTL capped by maxTtl, hit counts and a purge of expired entries; only the service role reads and writes it.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Model responses cached by a key the application derives from the request
-- (a SHA-256 of the model, the prompt and the settings). Entries hold prompts
-- and outputs, so only the service role reads and writes them.
create table if not exists "better_supabase"."ai_cache_entries" (
  "key" text primary key check (length("key") between 1 and 256),
  "organization_id" uuid,
  "kind" text not null default 'generate' check ("kind" in ('generate', 'stream', 'embed', 'other')),
  "model" text check (length("model") <= 200),
  "value" jsonb not null check (octet_length("value"::text) <= 1048576),
  "hits" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "last_hit_at" timestamptz,
  "expires_at" timestamptz not null
);
create index if not exists ai_cache_entries_expires_idx on "better_supabase"."ai_cache_entries" ("expires_at");
create index if not exists ai_cache_entries_tenant_idx on "better_supabase"."ai_cache_entries" ("organization_id");
alter table "better_supabase"."ai_cache_entries" enable row level security;
revoke all on "better_supabase"."ai_cache_entries" from anon, authenticated;
grant all on "better_supabase"."ai_cache_entries" to service_role;

-- The entry under key, or null when there is none or it expired; counts the hit.
create or replace function "better_supabase"."ai_cache_get"(key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_cache_entries"%rowtype;
begin
  update "better_supabase"."ai_cache_entries" x set "hits" = x."hits" + 1, "last_hit_at" = now()
  where x."key" = ai_cache_get.key and x."expires_at" > now()
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object('key', v_row."key", 'organization_id', v_row."organization_id", 'kind', v_row."kind", 'model', v_row."model", 'value', v_row."value", 'hits', v_row."hits", 'created_at', v_row."created_at", 'last_hit_at', v_row."last_hit_at", 'expires_at', v_row."expires_at");
end;
$$;
revoke execute on function "better_supabase"."ai_cache_get"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_cache_get"(text) to service_role;

-- Stores or replaces the entry under key for ttl seconds, at most 604800.
create or replace function "better_supabase"."ai_cache_set"(key text, value jsonb, ttl integer, tenant uuid default null, kind text default 'generate', model text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_cache_entries"%rowtype;
begin
  if ai_cache_set.ttl is null or ai_cache_set.ttl < 1 then
    raise exception 'ttl must be at least one second' using errcode = '22023', hint = 'AI_CACHE_INVALID';
  end if;
  insert into "better_supabase"."ai_cache_entries" ("key", "organization_id", "kind", "model", "value", "expires_at")
  values (ai_cache_set.key, ai_cache_set.tenant, coalesce(ai_cache_set.kind, 'generate'), ai_cache_set.model, ai_cache_set.value,
    now() + make_interval(secs => least(ai_cache_set.ttl, 604800)))
  on conflict ("key") do update set
    "organization_id" = excluded."organization_id",
    "kind" = excluded."kind",
    "model" = excluded."model",
    "value" = excluded."value",
    "hits" = 0,
    "created_at" = now(),
    "last_hit_at" = null,
    "expires_at" = excluded."expires_at"
  returning * into v_row;
  return jsonb_build_object('key', v_row."key", 'organization_id', v_row."organization_id", 'kind', v_row."kind", 'model', v_row."model", 'value', v_row."value", 'hits', v_row."hits", 'created_at', v_row."created_at", 'last_hit_at', v_row."last_hit_at", 'expires_at', v_row."expires_at") - 'value';
end;
$$;
revoke execute on function "better_supabase"."ai_cache_set"(text, jsonb, integer, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_cache_set"(text, jsonb, integer, uuid, text, text) to service_role;

-- Deletes one key, or every entry of a tenant (or with a model), and returns how many.
create or replace function "better_supabase"."ai_cache_delete"(key text default null, tenant uuid default null, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if ai_cache_delete.key is null and ai_cache_delete.tenant is null and ai_cache_delete.model is null then
    raise exception 'name a key, a tenant or a model' using errcode = '22023', hint = 'AI_CACHE_INVALID';
  end if;
  delete from "better_supabase"."ai_cache_entries" x
  where (ai_cache_delete.key is null or x."key" = ai_cache_delete.key)
    and (ai_cache_delete.tenant is null or x."organization_id" = ai_cache_delete.tenant)
    and (ai_cache_delete.model is null or x."model" = ai_cache_delete.model);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."ai_cache_delete"(text, uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ai_cache_delete"(text, uuid, text) to service_role;

-- Deletes up to batch expired entries and returns how many; schedule it.
create or replace function "better_supabase"."purge_ai_cache"(batch integer default 5000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."ai_cache_entries" x
  where x."key" in (
    select y."key" from "better_supabase"."ai_cache_entries" y
    where y."expires_at" <= now()
    order by y."expires_at"
    limit least(greatest(purge_ai_cache.batch, 1), 50000)
    for update skip locked
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_ai_cache"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_ai_cache"(integer) to service_role;

-- sql.modules.ai-cache.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."ai_cache_get"(key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_cache_get"($1) $$;
revoke execute on function "api"."ai_cache_get"(text) from public, anon, authenticated;
grant execute on function "api"."ai_cache_get"(text) to service_role;

create or replace function "api"."ai_cache_set"(key text, value jsonb, ttl integer, tenant uuid default null, kind text default 'generate', model text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_cache_set"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."ai_cache_set"(text, jsonb, integer, uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."ai_cache_set"(text, jsonb, integer, uuid, text, text) to service_role;

create or replace function "api"."ai_cache_delete"(key text default null, tenant uuid default null, model text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ai_cache_delete"($1, $2, $3) $$;
revoke execute on function "api"."ai_cache_delete"(text, uuid, text) from public, anon, authenticated;
grant execute on function "api"."ai_cache_delete"(text, uuid, text) to service_role;

create or replace function "api"."purge_ai_cache"(batch integer default 5000)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_ai_cache"($1) $$;
revoke execute on function "api"."purge_ai_cache"(integer) from public, anon, authenticated;
grant execute on function "api"."purge_ai_cache"(integer) to service_role;

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
