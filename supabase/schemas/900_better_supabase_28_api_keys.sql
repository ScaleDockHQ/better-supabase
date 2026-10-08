-- better-supabase module: api-keys (0.5.1)
-- @bs-module api-keys@3 managed
-- Hashed API keys for tenants and users with scopes, expiry, rotation with a grace period, a per-key rate limit and throttled last-used tracking. verify_api_key() backs apiKeyResolver; has_scope() and api_key_tenant() go in policies.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- API keys: `<prefix>_<public id>_<secret>`. Only the SHA-256 of the secret
-- is stored. A key acts as its user (user_id), as its tenant (organization_id
-- without user_id), or as a user inside one tenant (both).
create table if not exists "better_supabase"."api_keys" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid,
  "user_id" uuid references auth.users (id) on delete cascade,
  "name" text not null check (length(trim("name")) > 0),
  "prefix" text not null check ("prefix" ~ '^[a-z][a-z0-9]*$'),
  "public_id" text not null unique check ("public_id" ~ '^[0-9a-f]{16}$'),
  "secret_hash" text not null check ("secret_hash" ~ '^[0-9a-f]{64}$'),
  "scopes" text[] not null default '{}',
  "rate_limit" integer check ("rate_limit" > 0),
  "window_start" timestamptz,
  "window_hits" integer not null default 0,
  "expires_at" timestamptz,
  "last_used_at" timestamptz,
  "revoked_at" timestamptz,
  "rotated_from" uuid references "better_supabase"."api_keys" ("id") on delete set null,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  check ("organization_id" is not null or "user_id" is not null)
);
-- verify_api_key updates the counters on every request; free space on each
-- page keeps those updates HOT (no index writes).
alter table "better_supabase"."api_keys" set (fillfactor = 80);
create index if not exists api_keys_tenant_idx on "better_supabase"."api_keys" ("organization_id");
create index if not exists api_keys_user_idx on "better_supabase"."api_keys" ("user_id");
create index if not exists api_keys_rotated_from_idx on "better_supabase"."api_keys" ("rotated_from");
create index if not exists api_keys_created_by_idx on "better_supabase"."api_keys" ("created_by");
alter table "better_supabase"."api_keys" enable row level security;
revoke all on "better_supabase"."api_keys" from anon, authenticated;
grant all on "better_supabase"."api_keys" to service_role;

-- Creates a key. TypeScript generates the public id and the secret and sends
-- only the secret's SHA-256. A tenant key needs api_keys.manage; a personal
-- key in a tenant needs api_keys.own there.
create or replace function "better_supabase"."create_api_key"(
  name text,
  public_id text,
  secret_hash text,
  tenant uuid default null,
  personal boolean default false,
  scopes text[] default '{}',
  expires_at timestamptz default null,
  rate_limit integer default null,
  prefix text default 'bs'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner uuid := case when personal then auth.uid() end;
  created "better_supabase"."api_keys";
begin
  if personal and owner is null then
    raise exception 'Sign in to create a personal API key' using errcode = '42501', hint = 'API_KEY_SIGN_IN';
  end if;
  if not personal and tenant is null then
    raise exception 'A tenant API key needs a tenant' using errcode = '22023', hint = 'API_KEY_TENANT_REQUIRED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if not personal and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.manage'), false) then
      raise exception 'Not allowed to manage API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is not null and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.own'), false) then
      raise exception 'Not allowed to create API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is null and exists (
      select 1 from better_supabase.member_organization_ids() as m(id)
      where m.id not in (select better_supabase.tenant_ids_with('api_keys.own'))
    ) then
      raise exception 'Not allowed to create API keys for every tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
  end if;
  if expires_at is not null and expires_at <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at")
  values (tenant, owner, create_api_key.name, create_api_key.prefix, create_api_key.public_id, create_api_key.secret_hash, coalesce(create_api_key.scopes, '{}'), create_api_key.rate_limit, create_api_key.expires_at)
  returning * into created;
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$$;

-- A tenant's keys for its managers, or the caller's own keys.
create or replace function "better_supabase"."list_api_keys"(tenant uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- One plain filter per branch, so each reads through the tenant or user index.
  if list_api_keys.tenant is null then
    return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', k."id",
    'organization_id', k."organization_id",
    'user_id', k."user_id",
    'name', k."name",
    'prefix', k."prefix",
    'public_id', k."public_id",
    'scopes', to_jsonb(k."scopes"),
    'rate_limit', k."rate_limit",
    'expires_at', k."expires_at",
    'last_used_at', k."last_used_at",
    'revoked_at', k."revoked_at",
    'rotated_from', k."rotated_from",
    'created_by', k."created_by",
    'created_at', k."created_at",
    'state', case
      when k."revoked_at" is not null and k."revoked_at" <= now() then 'revoked'
      when k."expires_at" is not null and k."expires_at" <= now() then 'expired'
      when k."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = k."id" order by s."created_at" desc limit 1)
  ) order by k."created_at" desc), '[]'::jsonb)
      from "better_supabase"."api_keys" k where k."user_id" = auth.uid());
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_api_keys.tenant, 'api_keys.manage'), false) then
    return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', k."id",
    'organization_id', k."organization_id",
    'user_id', k."user_id",
    'name', k."name",
    'prefix', k."prefix",
    'public_id', k."public_id",
    'scopes', to_jsonb(k."scopes"),
    'rate_limit', k."rate_limit",
    'expires_at', k."expires_at",
    'last_used_at', k."last_used_at",
    'revoked_at', k."revoked_at",
    'rotated_from', k."rotated_from",
    'created_by', k."created_by",
    'created_at', k."created_at",
    'state', case
      when k."revoked_at" is not null and k."revoked_at" <= now() then 'revoked'
      when k."expires_at" is not null and k."expires_at" <= now() then 'expired'
      when k."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = k."id" order by s."created_at" desc limit 1)
  ) order by k."created_at" desc), '[]'::jsonb)
      from "better_supabase"."api_keys" k where k."organization_id" = list_api_keys.tenant);
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', k."id",
    'organization_id', k."organization_id",
    'user_id', k."user_id",
    'name', k."name",
    'prefix', k."prefix",
    'public_id', k."public_id",
    'scopes', to_jsonb(k."scopes"),
    'rate_limit', k."rate_limit",
    'expires_at', k."expires_at",
    'last_used_at', k."last_used_at",
    'revoked_at', k."revoked_at",
    'rotated_from', k."rotated_from",
    'created_by', k."created_by",
    'created_at', k."created_at",
    'state', case
      when k."revoked_at" is not null and k."revoked_at" <= now() then 'revoked'
      when k."expires_at" is not null and k."expires_at" <= now() then 'expired'
      when k."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = k."id" order by s."created_at" desc limit 1)
  ) order by k."created_at" desc), '[]'::jsonb)
    from "better_supabase"."api_keys" k where k."organization_id" = list_api_keys.tenant and k."user_id" = auth.uid());
end;
$$;

create or replace function "better_supabase"."revoke_api_key"(key uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  found "better_supabase"."api_keys";
begin
  select * into found from "better_supabase"."api_keys" k where k."id" = revoke_api_key.key;
  if found."id" is null or not ((found."organization_id" is not null and coalesce(better_supabase.can('tenant', found."organization_id", 'api_keys.manage'), false)) or coalesce(found."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  update "better_supabase"."api_keys" k set "revoked_at" = now()
  where k."id" = found."id" and (k."revoked_at" is null or k."revoked_at" > now());
  return true;
end;
$$;

-- Replaces a key with a new secret. The old key keeps working for grace,
-- so deployments can switch over.
create or replace function "better_supabase"."rotate_api_key"(
  key uuid,
  public_id text,
  secret_hash text,
  grace interval default interval '1 day'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  old "better_supabase"."api_keys";
  created "better_supabase"."api_keys";
begin
  select * into old from "better_supabase"."api_keys" k where k."id" = rotate_api_key.key for update;
  if old."id" is null or not ((old."organization_id" is not null and coalesce(better_supabase.can('tenant', old."organization_id", 'api_keys.manage'), false)) or coalesce(old."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  if old."revoked_at" is not null and old."revoked_at" <= now() then
    raise exception 'A revoked API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_REVOKED';
  end if;
  if old."expires_at" is not null and old."expires_at" <= now() then
    raise exception 'An expired API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  if grace is null or grace < interval '0' then
    raise exception 'grace must be zero or more' using errcode = '22023', hint = 'API_KEY_GRACE';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at", "rotated_from")
  values (old."organization_id", old."user_id", old."name", old."prefix", rotate_api_key.public_id, rotate_api_key.secret_hash, old."scopes", old."rate_limit", old."expires_at", old."id")
  returning * into created;
  update "better_supabase"."api_keys" k set "revoked_at" = now() + grace where k."id" = old."id";
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$$;

-- Server-side: checks a presented key and counts the request. Returns
-- { status: 'ok', key } or { status: 'invalid' | 'rate_limited', retry_after }.
-- It never raises for a bad key, so the counter update commits.
create or replace function "better_supabase"."verify_api_key"(public_id text, secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  found "better_supabase"."api_keys";
  started timestamptz;
  hits integer;
begin
  select * into found from "better_supabase"."api_keys" k where k."public_id" = verify_api_key.public_id;
  if found."id" is null
    or found."secret_hash" <> verify_api_key.secret_hash
    or (found."expires_at" is not null and found."expires_at" <= now())
    or (found."revoked_at" is not null and found."revoked_at" <= now())
    or (found."user_id" is not null and better_supabase.user_disabled(found."user_id"))
    or (found."organization_id" is not null and better_supabase.tenant_disabled(found."organization_id"))
    or (found."user_id" is not null and found."organization_id" is not null
      and better_supabase.organization_member_role(found."organization_id", found."user_id") is null)
  then
    return jsonb_build_object('status', 'invalid');
  end if;
  if found."rate_limit" is not null then
    -- One update counts the hit and, for an allowed request, touches last_used_at.
    update "better_supabase"."api_keys" k set
      "window_start" = case when (k."window_start" is null or k."window_start" + interval '1 minute' <= now()) then now() else k."window_start" end,
      "window_hits" = case when (k."window_start" is null or k."window_start" + interval '1 minute' <= now()) then 1 else k."window_hits" + 1 end,
      "last_used_at" = case when case when (k."window_start" is null or k."window_start" + interval '1 minute' <= now()) then 1 else k."window_hits" + 1 end <= k."rate_limit" and (k."last_used_at" is null or k."last_used_at" + interval '60 seconds' <= now()) then now() else k."last_used_at" end
    where k."id" = found."id"
    returning k."window_start", k."window_hits" into started, hits;
    if hits > found."rate_limit" then
      return jsonb_build_object(
        'status', 'rate_limited',
        'retry_after', greatest(1, ceil(extract(epoch from started + interval '1 minute' - now()))::integer)
      );
    end if;
  elsif (found."last_used_at" is null or found."last_used_at" + interval '60 seconds' <= now()) then
    update "better_supabase"."api_keys" k set "last_used_at" = now() where k."id" = found."id";
  end if;
  return jsonb_build_object('status', 'ok', 'key', jsonb_build_object(
    'id', found."id",
    'organization_id', found."organization_id",
    'user_id', found."user_id",
    'name', found."name",
    'prefix', found."prefix",
    'public_id', found."public_id",
    'scopes', to_jsonb(found."scopes"),
    'rate_limit', found."rate_limit",
    'expires_at', found."expires_at",
    'last_used_at', found."last_used_at",
    'revoked_at', found."revoked_at",
    'rotated_from', found."rotated_from",
    'created_by', found."created_by",
    'created_at', found."created_at",
    'state', case
      when found."revoked_at" is not null and found."revoked_at" <= now() then 'revoked'
      when found."expires_at" is not null and found."expires_at" <= now() then 'expired'
      when found."revoked_at" is not null then 'grace'
      else 'active'
    end
  ));
end;
$$;

-- For policies: whether the request's API key carries scope. Requests
-- without an API key (a signed-in user) are not limited by scopes. Wrap the
-- calls in (select ...) so they run once per statement, not once per row:
--   using (organization_id = (select better_supabase.api_key_tenant()) and (select better_supabase.has_scope('deals:read')))
create or replace function "better_supabase"."has_scope"(scope text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when auth.jwt() -> 'api_key' is null then true
    else coalesce(auth.jwt() -> 'api_key' -> 'scopes', '[]'::jsonb) ?| array['*', has_scope.scope]
  end
$$;

-- The tenant of the request's tenant API key, or null.
create or replace function "better_supabase"."api_key_tenant"()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(auth.jwt() -> 'api_key' ->> 'organization_id', '')::uuid
$$;

revoke execute on function "better_supabase"."create_api_key"(text, text, text, uuid, boolean, text[], timestamptz, integer, text) from public, anon;
revoke execute on function "better_supabase"."list_api_keys"(uuid) from public, anon;
revoke execute on function "better_supabase"."revoke_api_key"(uuid) from public, anon;
revoke execute on function "better_supabase"."rotate_api_key"(uuid, text, text, interval) from public, anon;
revoke execute on function "better_supabase"."verify_api_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."create_api_key"(text, text, text, uuid, boolean, text[], timestamptz, integer, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_api_keys"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."revoke_api_key"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."rotate_api_key"(uuid, text, text, interval) to authenticated, service_role;
grant execute on function "better_supabase"."verify_api_key"(text, text) to service_role;
grant execute on function "better_supabase"."has_scope"(text) to anon, authenticated, service_role;
grant execute on function "better_supabase"."api_key_tenant"() to anon, authenticated, service_role;

-- sql.modules.api-keys.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_api_key"(name text, public_id text, secret_hash text, tenant uuid default null, personal boolean default false, scopes text[] default '{}', expires_at timestamptz default null, rate_limit integer default null, prefix text default 'bs')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_api_key"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."create_api_key"(text, text, text, uuid, boolean, text[], timestamptz, integer, text) from public, anon;
grant execute on function "api"."create_api_key"(text, text, text, uuid, boolean, text[], timestamptz, integer, text) to authenticated, service_role;

create or replace function "api"."list_api_keys"(tenant uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_api_keys"($1) $$;
revoke execute on function "api"."list_api_keys"(uuid) from public, anon;
grant execute on function "api"."list_api_keys"(uuid) to authenticated, service_role;

create or replace function "api"."revoke_api_key"(key uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_api_key"($1) $$;
revoke execute on function "api"."revoke_api_key"(uuid) from public, anon;
grant execute on function "api"."revoke_api_key"(uuid) to authenticated, service_role;

create or replace function "api"."rotate_api_key"(key uuid, public_id text, secret_hash text, grace interval default interval '1 day')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_api_key"($1, $2, $3, $4) $$;
revoke execute on function "api"."rotate_api_key"(uuid, text, text, interval) from public, anon;
grant execute on function "api"."rotate_api_key"(uuid, text, text, interval) to authenticated, service_role;

create or replace function "api"."verify_api_key"(public_id text, secret_hash text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."verify_api_key"($1, $2) $$;
revoke execute on function "api"."verify_api_key"(text, text) from public, anon, authenticated;
grant execute on function "api"."verify_api_key"(text, text) to service_role;

create or replace function "api"."has_scope"(scope text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."has_scope"($1) $$;
revoke execute on function "api"."has_scope"(text) from public;
grant execute on function "api"."has_scope"(text) to anon, authenticated, service_role;

create or replace function "api"."api_key_tenant"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."api_key_tenant"() $$;
revoke execute on function "api"."api_key_tenant"() from public;
grant execute on function "api"."api_key_tenant"() to anon, authenticated, service_role;

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
