-- ==== alone: schema supabase/schemas/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block oauth-server@1 managed
-- @bsb-hash sha256:8e8a9f38db3cc3f4bd335a0ae66dbfe8853d0b8dd72c35a24eae8c4962795bda
-- Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOAuthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- OAuth 2.1 authorization server storage: registered clients (RFC 7591)
-- with hashed secrets, a user's grant per client, single-use authorization
-- codes bound to a PKCE S256 challenge (RFC 7636), device codes (RFC 8628)
-- and a revocation list of access token jtis. Tokens are issued elsewhere.
create table if not exists "better_supabase"."oauth_clients" (
  "id" uuid primary key default gen_random_uuid(),
  "client_id" text not null unique check ("client_id" ~ '^[A-Za-z0-9._~-]{8,128}$'),
  "secret_hash" text check ("secret_hash" ~ '^[0-9a-f]{64}$'),
  "registration_token_hash" text check ("registration_token_hash" ~ '^[0-9a-f]{64}$'),
  "client_name" text check (length("client_name") <= 200),
  "redirect_uris" text[] not null default '{}',
  "grant_types" text[] not null default '{authorization_code}'
    check ("grant_types" <@ array['authorization_code', 'refresh_token', 'client_credentials', 'urn:ietf:params:oauth:grant-type:device_code']::text[]),
  "token_endpoint_auth_method" text not null default 'client_secret_basic'
    check ("token_endpoint_auth_method" in ('none', 'client_secret_basic', 'client_secret_post')),
  "scope" text,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("token_endpoint_auth_method" = 'none') = ("secret_hash" is null))
);
create index if not exists oauth_clients_created_by_idx on "better_supabase"."oauth_clients" ("created_by");
alter table "better_supabase"."oauth_clients" enable row level security;
revoke all on "better_supabase"."oauth_clients" from public, anon, authenticated;
grant all on "better_supabase"."oauth_clients" to service_role;

create table if not exists "better_supabase"."oauth_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scopes" text[] not null default '{}',
  "resource" text[] not null default '{}',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists oauth_grants_active_idx on "better_supabase"."oauth_grants" ("user_id", "client_id") where "revoked_at" is null;
create index if not exists oauth_grants_client_idx on "better_supabase"."oauth_grants" ("client_id");
alter table "better_supabase"."oauth_grants" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_grants_user_idx on "better_supabase"."oauth_grants" ("user_id");
alter table "better_supabase"."oauth_grants" enable row level security;
revoke all on "better_supabase"."oauth_grants" from public, anon, authenticated;
grant all on "better_supabase"."oauth_grants" to service_role;

create table if not exists "better_supabase"."oauth_authorization_codes" (
  "code_hash" text primary key check ("code_hash" ~ '^[0-9a-f]{64}$'),
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "grant_id" uuid not null references "better_supabase"."oauth_grants" ("id") on delete cascade,
  "redirect_uri" text,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "code_challenge" text not null check ("code_challenge" ~ '^[A-Za-z0-9_-]{43}$'),
  "nonce" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_authorization_codes_expires_idx on "better_supabase"."oauth_authorization_codes" ("expires_at");
create index if not exists oauth_authorization_codes_grant_idx on "better_supabase"."oauth_authorization_codes" ("grant_id");
create index if not exists oauth_authorization_codes_client_idx on "better_supabase"."oauth_authorization_codes" ("client_id");
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_authorization_codes_user_idx on "better_supabase"."oauth_authorization_codes" ("user_id");
alter table "better_supabase"."oauth_authorization_codes" enable row level security;
revoke all on "better_supabase"."oauth_authorization_codes" from public, anon, authenticated;
grant all on "better_supabase"."oauth_authorization_codes" to service_role;

create table if not exists "better_supabase"."oauth_device_codes" (
  "device_code_hash" text primary key check ("device_code_hash" ~ '^[0-9a-f]{64}$'),
  "user_code" text not null check ("user_code" ~ '^[A-Z0-9]{6,12}$'),
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'denied')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "grant_id" uuid references "better_supabase"."oauth_grants" ("id") on delete cascade,
  "poll_interval" integer not null default 5 check ("poll_interval" between 1 and 300),
  "last_polled_at" timestamptz,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check (("status" = 'approved') = ("grant_id" is not null))
);
create unique index if not exists oauth_device_codes_user_code_idx on "better_supabase"."oauth_device_codes" ("user_code") where "status" = 'pending';
create index if not exists oauth_device_codes_expires_idx on "better_supabase"."oauth_device_codes" ("expires_at");
create index if not exists oauth_device_codes_grant_idx on "better_supabase"."oauth_device_codes" ("grant_id");
create index if not exists oauth_device_codes_client_idx on "better_supabase"."oauth_device_codes" ("client_id");
alter table "better_supabase"."oauth_device_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_device_codes_user_idx on "better_supabase"."oauth_device_codes" ("user_id");
alter table "better_supabase"."oauth_device_codes" enable row level security;
revoke all on "better_supabase"."oauth_device_codes" from public, anon, authenticated;
grant all on "better_supabase"."oauth_device_codes" to service_role;

create table if not exists "better_supabase"."oauth_revocations" (
  "jti" text primary key check (length("jti") between 1 and 256),
  "grant_id" uuid,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_revocations_expires_idx on "better_supabase"."oauth_revocations" ("expires_at");
alter table "better_supabase"."oauth_revocations" enable row level security;
revoke all on "better_supabase"."oauth_revocations" from public, anon, authenticated;
grant all on "better_supabase"."oauth_revocations" to service_role;

-- The user's active grant for the client, widened to the scopes; a new one
-- when there is none. Only the definer functions below call it.
drop function if exists "better_supabase"."oauth_grant_for"(uuid, text, text[]);
create or replace function "better_supabase"."oauth_grant_for"(user_id uuid, client_id text, scopes text[], resource text[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g
  set "scopes" = array(select distinct s from unnest(g."scopes" || oauth_grant_for.scopes) s order by s),
    "resource" = array(select distinct r from unnest(g."resource" || coalesce(oauth_grant_for.resource, '{}')) r order by r),
    "updated_at" = now()
  where g."user_id" = oauth_grant_for.user_id
    and g."client_id" = oauth_grant_for.client_id
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    insert into "better_supabase"."oauth_grants" ("user_id", "client_id", "scopes", "resource")
    values (oauth_grant_for.user_id, oauth_grant_for.client_id,
      array(select distinct s from unnest(oauth_grant_for.scopes) s order by s),
      array(select distinct r from unnest(coalesce(oauth_grant_for.resource, '{}')) r order by r))
    returning * into v_row;
    null;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."oauth_grant_for"(uuid, text, text[], text[]) from public, anon, authenticated, service_role;

-- Registers a client (RFC 7591). The secret and registration token arrive hashed.
create or replace function "better_supabase"."register_oauth_client"(
  client_id text, secret_hash text, registration_token_hash text, client_name text,
  redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text,
  metadata jsonb, created_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_clients" ("client_id", "secret_hash", "registration_token_hash", "client_name",
    "redirect_uris", "grant_types", "token_endpoint_auth_method", "scope", "metadata", "created_by")
  values (register_oauth_client.client_id, register_oauth_client.secret_hash,
    register_oauth_client.registration_token_hash, register_oauth_client.client_name,
    coalesce(register_oauth_client.redirect_uris, '{}'),
    coalesce(register_oauth_client.grant_types, '{authorization_code}'),
    coalesce(register_oauth_client.token_endpoint_auth_method, 'client_secret_basic'),
    register_oauth_client.scope, coalesce(register_oauth_client.metadata, '{}'::jsonb),
    register_oauth_client.created_by)
  returning * into v_row;
  null;
  return jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) to service_role;

-- A client without its hashes, or null.
create or replace function "better_supabase"."oauth_client"(client_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at") from "better_supabase"."oauth_clients" c where c."client_id" = oauth_client.client_id);
end;
$$;
revoke execute on function "better_supabase"."oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_client"(text) to service_role;

-- The client when the secret hash matches (null secret for a public client), or null.
create or replace function "better_supabase"."verify_oauth_client"(client_id text, secret_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at")
    from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_client.client_id
      and c."secret_hash" is not distinct from verify_oauth_client.secret_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_client"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_client"(text, text) to service_role;

-- Whether the registration access token (RFC 7592) belongs to the client.
create or replace function "better_supabase"."verify_oauth_registration_token"(client_id text, token_hash text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_registration_token.client_id
      and c."registration_token_hash" = verify_oauth_registration_token.token_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_registration_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_registration_token"(text, text) to service_role;

-- Replaces a client's metadata (RFC 7592); null keeps a value. Null when unknown.
create or replace function "better_supabase"."update_oauth_client"(
  client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set
    "client_name" = coalesce(update_oauth_client.client_name, c."client_name"),
    "redirect_uris" = coalesce(update_oauth_client.redirect_uris, c."redirect_uris"),
    "grant_types" = coalesce(update_oauth_client.grant_types, c."grant_types"),
    "scope" = coalesce(update_oauth_client.scope, c."scope"),
    "metadata" = coalesce(update_oauth_client.metadata, c."metadata"),
    "updated_at" = now()
  where c."client_id" = update_oauth_client.client_id
  returning c.* into v_row;
  return case when v_row."id" is null then null else jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at") end;
end;
$$;
revoke execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) to service_role;

-- Sets a new secret hash for a confidential client; false when unknown or public.
create or replace function "better_supabase"."rotate_oauth_client_secret"(client_id text, secret_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set "secret_hash" = rotate_oauth_client_secret.secret_hash, "updated_at" = now()
  where c."client_id" = rotate_oauth_client_secret.client_id and c."token_endpoint_auth_method" <> 'none';
  return found;
end;
$$;
revoke execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) to service_role;

-- Deletes a client with its grants and codes; its tokens fail the grant check.
create or replace function "better_supabase"."delete_oauth_client"(client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_clients" c where c."client_id" = delete_oauth_client.client_id;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_oauth_client"(text) to service_role;

-- Stores an authorization code after consent, under the user's grant.
drop function if exists "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text);
create or replace function "better_supabase"."create_oauth_authorization_code"(
  code_hash text, client_id text, user_id uuid, redirect_uri text, scope text,
  code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_authorization_code.client_id
      and 'authorization_code' = any (c."grant_types")
      and (create_oauth_authorization_code.redirect_uri is null
        or create_oauth_authorization_code.redirect_uri = any (c."redirect_uris"))
  ) then
    raise exception 'the client is unknown, can''t use codes, or didn''t register the redirect URI' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  v_grant := "better_supabase"."oauth_grant_for"(create_oauth_authorization_code.user_id,
    create_oauth_authorization_code.client_id, array(select s from unnest(regexp_split_to_array(btrim(coalesce(create_oauth_authorization_code.scope, '')), '\s+')) s where s <> ''),
    coalesce(create_oauth_authorization_code.resource, '{}'));
  insert into "better_supabase"."oauth_authorization_codes" ("code_hash", "client_id", "user_id", "grant_id", "redirect_uri",
    "scope", "resource", "code_challenge", "nonce", "expires_at")
  values (create_oauth_authorization_code.code_hash, create_oauth_authorization_code.client_id,
    create_oauth_authorization_code.user_id, v_grant, create_oauth_authorization_code.redirect_uri,
    coalesce(create_oauth_authorization_code.scope, ''), coalesce(create_oauth_authorization_code.resource, '{}'),
    create_oauth_authorization_code.code_challenge,
    create_oauth_authorization_code.nonce, now() + create_oauth_authorization_code.ttl);
  return jsonb_build_object('grantId', v_grant);
end;
$$;
revoke execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) to service_role;

-- Consumes a code once. code_challenge is S256 of the presented verifier.
-- A code presented twice revokes its grant (RFC 9700 section 4.5).
drop function if exists "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text);
create or replace function "better_supabase"."redeem_oauth_authorization_code"(
  code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code "better_supabase"."oauth_authorization_codes";
  v_grant "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_code from "better_supabase"."oauth_authorization_codes" a
  where a."code_hash" = redeem_oauth_authorization_code.code_hash
  for update;
  if v_code."code_hash" is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_code."consumed_at" is not null then
    update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
    where g."id" = v_code."grant_id" and g."revoked_at" is null
    returning g.* into v_grant;
    if v_grant."id" is not null then
      null;
    end if;
    return jsonb_build_object('status', 'invalid', 'replayed', true);
  end if;
  update "better_supabase"."oauth_authorization_codes" a set "consumed_at" = now()
  where a."code_hash" = v_code."code_hash";
  if v_code."expires_at" <= now()
    or v_code."client_id" <> redeem_oauth_authorization_code.client_id
    or v_code."redirect_uri" is distinct from redeem_oauth_authorization_code.redirect_uri
    or v_code."code_challenge" <> redeem_oauth_authorization_code.code_challenge
    or not exists (
      select 1 from "better_supabase"."oauth_grants" g
      where g."id" = v_code."grant_id" and g."revoked_at" is null
    ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- RFC 8707 section 2.2: a token request may narrow the resources of the
  -- code but never widen them.
  if redeem_oauth_authorization_code.resource is not null
    and not redeem_oauth_authorization_code.resource <@ v_code."resource" then
    return jsonb_build_object('status', 'invalid', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_code."user_id", 'clientId', v_code."client_id",
    'grantId', v_code."grant_id", 'scope', v_code."scope", 'nonce', v_code."nonce",
    'resource', to_jsonb(coalesce(redeem_oauth_authorization_code.resource, v_code."resource")));
end;
$$;
revoke execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) to service_role;

-- Starts a device authorization (RFC 8628 section 3.2).
drop function if exists "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer);
create or replace function "better_supabase"."create_oauth_device_code"(
  device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5,
  resource text[] default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_device_code.client_id
      and 'urn:ietf:params:oauth:grant-type:device_code' = any (c."grant_types")
  ) then
    raise exception 'the client is unknown or can''t use the device flow' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  insert into "better_supabase"."oauth_device_codes" ("device_code_hash", "user_code", "client_id", "scope",
    "resource", "poll_interval", "expires_at")
  values (create_oauth_device_code.device_code_hash, create_oauth_device_code.user_code,
    create_oauth_device_code.client_id, coalesce(create_oauth_device_code.scope, ''),
    coalesce(create_oauth_device_code.resource, '{}'),
    coalesce(create_oauth_device_code.poll_interval, 5), now() + create_oauth_device_code.ttl);
  return true;
end;
$$;
revoke execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) to service_role;

-- The pending request behind a user code, for the verification page, or null.
create or replace function "better_supabase"."oauth_device_request"(user_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('clientId', d."client_id", 'scope', d."scope", 'resource', to_jsonb(d."resource"), 'expiresAt', d."expires_at")
    from "better_supabase"."oauth_device_codes" d
    where d."user_code" = oauth_device_request.user_code
      and d."status" = 'pending'
      and d."expires_at" > now()
  );
end;
$$;
revoke execute on function "better_supabase"."oauth_device_request"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_device_request"(text) to service_role;

-- Approves or denies a pending user code for the signed-in user; false when
-- there is no such pending, unexpired code.
create or replace function "better_supabase"."decide_oauth_device_code"(user_code text, user_id uuid, approve boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."user_code" = decide_oauth_device_code.user_code
    and d."status" = 'pending'
    and d."expires_at" > now()
  for update;
  if v_device."device_code_hash" is null then
    return false;
  end if;
  if decide_oauth_device_code.approve then
    v_grant := "better_supabase"."oauth_grant_for"(decide_oauth_device_code.user_id, v_device."client_id",
      array(select s from unnest(regexp_split_to_array(btrim(coalesce(v_device."scope", '')), '\s+')) s where s <> ''), v_device."resource");
  end if;
  update "better_supabase"."oauth_device_codes" d set
    "status" = case when decide_oauth_device_code.approve then 'approved' else 'denied' end,
    "user_id" = decide_oauth_device_code.user_id,
    "grant_id" = v_grant
  where d."device_code_hash" = v_device."device_code_hash";
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) to service_role;

-- A token request's poll (RFC 8628 section 3.5): pending, slow_down,
-- access_denied, expired_token, invalid_grant, or ok once.
drop function if exists "better_supabase"."poll_oauth_device_code"(text, text);
create or replace function "better_supabase"."poll_oauth_device_code"(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."device_code_hash" = poll_oauth_device_code.device_code_hash
  for update;
  if v_device."device_code_hash" is null
    or v_device."client_id" <> poll_oauth_device_code.client_id
    or v_device."consumed_at" is not null then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if v_device."expires_at" <= now() then
    return jsonb_build_object('status', 'expired_token');
  end if;
  if v_device."status" = 'denied' then
    update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'access_denied');
  end if;
  if v_device."status" = 'pending' then
    if v_device."last_polled_at" is not null
      and v_device."last_polled_at" + make_interval(secs => v_device."poll_interval") > now() then
      update "better_supabase"."oauth_device_codes" d set "poll_interval" = least(d."poll_interval" + 5, 300), "last_polled_at" = now()
      where d."device_code_hash" = v_device."device_code_hash";
      return jsonb_build_object('status', 'slow_down', 'interval', least(v_device."poll_interval" + 5, 300));
    end if;
    update "better_supabase"."oauth_device_codes" d set "last_polled_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'authorization_pending', 'interval', v_device."poll_interval");
  end if;
  update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
  where d."device_code_hash" = v_device."device_code_hash";
  if not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id" = v_device."grant_id" and g."revoked_at" is null
  ) then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if poll_oauth_device_code.resource is not null
    and not poll_oauth_device_code.resource <@ v_device."resource" then
    return jsonb_build_object('status', 'invalid_grant', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_device."user_id", 'clientId', v_device."client_id",
    'grantId', v_device."grant_id", 'scope', v_device."scope",
    'resource', to_jsonb(coalesce(poll_oauth_device_code.resource, v_device."resource")));
end;
$$;
revoke execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) to service_role;

-- A user's grants, newest first; revoked ones only with include_revoked.
create or replace function "better_supabase"."list_oauth_grants"(user_id uuid, include_revoked boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = list_oauth_grants.user_id
      and (list_oauth_grants.include_revoked or g."revoked_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) to service_role;

-- Revokes a grant, which ends every token and code issued under it.
create or replace function "better_supabase"."revoke_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_oauth_grant.grant_id and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_grant"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_grant"(uuid) to service_role;

-- The signed-in user's active grants, for a "connected apps" page.
create or replace function "better_supabase"."my_oauth_grants"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = (select auth.uid())
      and g."revoked_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."my_oauth_grants"() from public, anon;
grant execute on function "better_supabase"."my_oauth_grants"() to authenticated, service_role;

-- Revokes one of the signed-in user's grants; false when it isn't theirs or active.
create or replace function "better_supabase"."revoke_my_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_my_oauth_grant.grant_id
    and g."user_id" = (select auth.uid())
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) to authenticated, service_role;

-- Adds an access token's jti to the revocation list until it expires.
create or replace function "better_supabase"."revoke_oauth_token"(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_revocations" ("jti", "grant_id", "expires_at")
  values (revoke_oauth_token.jti, revoke_oauth_token.grant_id, revoke_oauth_token.expires_at)
  on conflict ("jti") do update
    set "expires_at" = greatest("better_supabase"."oauth_revocations"."expires_at", excluded."expires_at");
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) to service_role;

-- True when the jti is on the revocation list, or the grant is revoked or
-- gone. A grant id that isn't a uuid counts as gone.
create or replace function "better_supabase"."is_oauth_token_revoked"(jti text, grant_id text default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."oauth_revocations" r where r."jti" = is_oauth_token_revoked.jti) then
    return true;
  end if;
  if is_oauth_token_revoked.grant_id is null then
    return false;
  end if;
  return not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id"::text = is_oauth_token_revoked.grant_id
      and g."revoked_at" is null
  );
end;
$$;
revoke execute on function "better_supabase"."is_oauth_token_revoked"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."is_oauth_token_revoked"(text, text) to service_role;

-- Deletes expired codes, device codes and revocation entries.
create or replace function "better_supabase"."purge_oauth_server"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_authorization_codes" a where a."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_device_codes" d where d."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_revocations" r where r."expires_at" < now();
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke execute on function "better_supabase"."purge_oauth_server"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_oauth_server"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block-data oauth-server
-- @bsb-hash sha256:fab570c8a0c09333723619c92dc55f7398532ffcd876d492a19b0cb2362b9a2f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('oauth-server', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block oauth-server@1 managed
-- @bsb-hash sha256:6a7e4f83ff5c7da2de1cb0605aaaf2af7da045723435738124401abbfc6233ba
-- Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOAuthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- OAuth 2.1 authorization server storage: registered clients (RFC 7591)
-- with hashed secrets, a user's grant per client, single-use authorization
-- codes bound to a PKCE S256 challenge (RFC 7636), device codes (RFC 8628)
-- and a revocation list of access token jtis. Tokens are issued elsewhere.
create table if not exists "better_supabase"."oauth_clients" (
  "id" uuid primary key default gen_random_uuid(),
  "client_id" text not null unique check ("client_id" ~ '^[A-Za-z0-9._~-]{8,128}$'),
  "secret_hash" text check ("secret_hash" ~ '^[0-9a-f]{64}$'),
  "registration_token_hash" text check ("registration_token_hash" ~ '^[0-9a-f]{64}$'),
  "client_name" text check (length("client_name") <= 200),
  "redirect_uris" text[] not null default '{}',
  "grant_types" text[] not null default '{authorization_code}'
    check ("grant_types" <@ array['authorization_code', 'refresh_token', 'client_credentials', 'urn:ietf:params:oauth:grant-type:device_code']::text[]),
  "token_endpoint_auth_method" text not null default 'client_secret_basic'
    check ("token_endpoint_auth_method" in ('none', 'client_secret_basic', 'client_secret_post')),
  "scope" text,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("token_endpoint_auth_method" = 'none') = ("secret_hash" is null))
);
create index if not exists oauth_clients_created_by_idx on "better_supabase"."oauth_clients" ("created_by");
alter table "better_supabase"."oauth_clients" enable row level security;
revoke all on "better_supabase"."oauth_clients" from public, anon, authenticated;
grant all on "better_supabase"."oauth_clients" to service_role;

create table if not exists "better_supabase"."oauth_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scopes" text[] not null default '{}',
  "resource" text[] not null default '{}',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists oauth_grants_active_idx on "better_supabase"."oauth_grants" ("user_id", "client_id") where "revoked_at" is null;
create index if not exists oauth_grants_client_idx on "better_supabase"."oauth_grants" ("client_id");
alter table "better_supabase"."oauth_grants" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_grants_user_idx on "better_supabase"."oauth_grants" ("user_id");
alter table "better_supabase"."oauth_grants" enable row level security;
revoke all on "better_supabase"."oauth_grants" from public, anon, authenticated;
grant all on "better_supabase"."oauth_grants" to service_role;

create table if not exists "better_supabase"."oauth_authorization_codes" (
  "code_hash" text primary key check ("code_hash" ~ '^[0-9a-f]{64}$'),
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "grant_id" uuid not null references "better_supabase"."oauth_grants" ("id") on delete cascade,
  "redirect_uri" text,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "code_challenge" text not null check ("code_challenge" ~ '^[A-Za-z0-9_-]{43}$'),
  "nonce" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_authorization_codes_expires_idx on "better_supabase"."oauth_authorization_codes" ("expires_at");
create index if not exists oauth_authorization_codes_grant_idx on "better_supabase"."oauth_authorization_codes" ("grant_id");
create index if not exists oauth_authorization_codes_client_idx on "better_supabase"."oauth_authorization_codes" ("client_id");
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_authorization_codes_user_idx on "better_supabase"."oauth_authorization_codes" ("user_id");
alter table "better_supabase"."oauth_authorization_codes" enable row level security;
revoke all on "better_supabase"."oauth_authorization_codes" from public, anon, authenticated;
grant all on "better_supabase"."oauth_authorization_codes" to service_role;

create table if not exists "better_supabase"."oauth_device_codes" (
  "device_code_hash" text primary key check ("device_code_hash" ~ '^[0-9a-f]{64}$'),
  "user_code" text not null check ("user_code" ~ '^[A-Z0-9]{6,12}$'),
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'denied')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "grant_id" uuid references "better_supabase"."oauth_grants" ("id") on delete cascade,
  "poll_interval" integer not null default 5 check ("poll_interval" between 1 and 300),
  "last_polled_at" timestamptz,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check (("status" = 'approved') = ("grant_id" is not null))
);
create unique index if not exists oauth_device_codes_user_code_idx on "better_supabase"."oauth_device_codes" ("user_code") where "status" = 'pending';
create index if not exists oauth_device_codes_expires_idx on "better_supabase"."oauth_device_codes" ("expires_at");
create index if not exists oauth_device_codes_grant_idx on "better_supabase"."oauth_device_codes" ("grant_id");
create index if not exists oauth_device_codes_client_idx on "better_supabase"."oauth_device_codes" ("client_id");
alter table "better_supabase"."oauth_device_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_device_codes_user_idx on "better_supabase"."oauth_device_codes" ("user_id");
alter table "better_supabase"."oauth_device_codes" enable row level security;
revoke all on "better_supabase"."oauth_device_codes" from public, anon, authenticated;
grant all on "better_supabase"."oauth_device_codes" to service_role;

create table if not exists "better_supabase"."oauth_revocations" (
  "jti" text primary key check (length("jti") between 1 and 256),
  "grant_id" uuid,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_revocations_expires_idx on "better_supabase"."oauth_revocations" ("expires_at");
alter table "better_supabase"."oauth_revocations" enable row level security;
revoke all on "better_supabase"."oauth_revocations" from public, anon, authenticated;
grant all on "better_supabase"."oauth_revocations" to service_role;

-- The user's active grant for the client, widened to the scopes; a new one
-- when there is none. Only the definer functions below call it.
drop function if exists "better_supabase"."oauth_grant_for"(uuid, text, text[]);
create or replace function "better_supabase"."oauth_grant_for"(user_id uuid, client_id text, scopes text[], resource text[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g
  set "scopes" = array(select distinct s from unnest(g."scopes" || oauth_grant_for.scopes) s order by s),
    "resource" = array(select distinct r from unnest(g."resource" || coalesce(oauth_grant_for.resource, '{}')) r order by r),
    "updated_at" = now()
  where g."user_id" = oauth_grant_for.user_id
    and g."client_id" = oauth_grant_for.client_id
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    insert into "better_supabase"."oauth_grants" ("user_id", "client_id", "scopes", "resource")
    values (oauth_grant_for.user_id, oauth_grant_for.client_id,
      array(select distinct s from unnest(oauth_grant_for.scopes) s order by s),
      array(select distinct r from unnest(coalesce(oauth_grant_for.resource, '{}')) r order by r))
    returning * into v_row;
    perform "better_supabase".emit_event('oauth_grant.created', jsonb_build_object('grantId', v_row."id"::text, 'userId', v_row."user_id"::text, 'clientId', v_row."client_id"), 'oauth-grants/' || v_row."id"::text, null, null, 'better-supabase/oauth-server');
  perform better_supabase.audit_event(
    event_type => 'oauth_grant.created',
    category => 'access',
    target_type => 'oauth_grant',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('grantId', v_row."id"::text, 'userId', v_row."user_id"::text, 'clientId', v_row."client_id"),
    actor_id => v_row."user_id"
  );
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."oauth_grant_for"(uuid, text, text[], text[]) from public, anon, authenticated, service_role;

-- Registers a client (RFC 7591). The secret and registration token arrive hashed.
create or replace function "better_supabase"."register_oauth_client"(
  client_id text, secret_hash text, registration_token_hash text, client_name text,
  redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text,
  metadata jsonb, created_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_clients" ("client_id", "secret_hash", "registration_token_hash", "client_name",
    "redirect_uris", "grant_types", "token_endpoint_auth_method", "scope", "metadata", "created_by")
  values (register_oauth_client.client_id, register_oauth_client.secret_hash,
    register_oauth_client.registration_token_hash, register_oauth_client.client_name,
    coalesce(register_oauth_client.redirect_uris, '{}'),
    coalesce(register_oauth_client.grant_types, '{authorization_code}'),
    coalesce(register_oauth_client.token_endpoint_auth_method, 'client_secret_basic'),
    register_oauth_client.scope, coalesce(register_oauth_client.metadata, '{}'::jsonb),
    register_oauth_client.created_by)
  returning * into v_row;
  perform "better_supabase".emit_event('oauth_client.registered', jsonb_build_object('clientId', v_row."client_id"), 'oauth-clients/' || v_row."client_id", null, null, 'better-supabase/oauth-server');
  perform better_supabase.audit_event(
    event_type => 'oauth_client.registered',
    category => 'security',
    target_type => 'oauth_client',
    record_id => v_row."client_id",
    metadata => jsonb_build_object('clientId', v_row."client_id")
  );
  return jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) to service_role;

-- A client without its hashes, or null.
create or replace function "better_supabase"."oauth_client"(client_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at") from "better_supabase"."oauth_clients" c where c."client_id" = oauth_client.client_id);
end;
$$;
revoke execute on function "better_supabase"."oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_client"(text) to service_role;

-- The client when the secret hash matches (null secret for a public client), or null.
create or replace function "better_supabase"."verify_oauth_client"(client_id text, secret_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at")
    from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_client.client_id
      and c."secret_hash" is not distinct from verify_oauth_client.secret_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_client"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_client"(text, text) to service_role;

-- Whether the registration access token (RFC 7592) belongs to the client.
create or replace function "better_supabase"."verify_oauth_registration_token"(client_id text, token_hash text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_registration_token.client_id
      and c."registration_token_hash" = verify_oauth_registration_token.token_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_registration_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_registration_token"(text, text) to service_role;

-- Replaces a client's metadata (RFC 7592); null keeps a value. Null when unknown.
create or replace function "better_supabase"."update_oauth_client"(
  client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set
    "client_name" = coalesce(update_oauth_client.client_name, c."client_name"),
    "redirect_uris" = coalesce(update_oauth_client.redirect_uris, c."redirect_uris"),
    "grant_types" = coalesce(update_oauth_client.grant_types, c."grant_types"),
    "scope" = coalesce(update_oauth_client.scope, c."scope"),
    "metadata" = coalesce(update_oauth_client.metadata, c."metadata"),
    "updated_at" = now()
  where c."client_id" = update_oauth_client.client_id
  returning c.* into v_row;
  return case when v_row."id" is null then null else jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at") end;
end;
$$;
revoke execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) to service_role;

-- Sets a new secret hash for a confidential client; false when unknown or public.
create or replace function "better_supabase"."rotate_oauth_client_secret"(client_id text, secret_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set "secret_hash" = rotate_oauth_client_secret.secret_hash, "updated_at" = now()
  where c."client_id" = rotate_oauth_client_secret.client_id and c."token_endpoint_auth_method" <> 'none';
  return found;
end;
$$;
revoke execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) to service_role;

-- Deletes a client with its grants and codes; its tokens fail the grant check.
create or replace function "better_supabase"."delete_oauth_client"(client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_clients" c where c."client_id" = delete_oauth_client.client_id;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('oauth_client.deleted', jsonb_build_object('clientId', delete_oauth_client.client_id), 'oauth-clients/' || delete_oauth_client.client_id, null, null, 'better-supabase/oauth-server');
  perform better_supabase.audit_event(
    event_type => 'oauth_client.deleted',
    category => 'security',
    target_type => 'oauth_client',
    record_id => delete_oauth_client.client_id,
    metadata => jsonb_build_object('clientId', delete_oauth_client.client_id)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_oauth_client"(text) to service_role;

-- Stores an authorization code after consent, under the user's grant.
drop function if exists "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text);
create or replace function "better_supabase"."create_oauth_authorization_code"(
  code_hash text, client_id text, user_id uuid, redirect_uri text, scope text,
  code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_authorization_code.client_id
      and 'authorization_code' = any (c."grant_types")
      and (create_oauth_authorization_code.redirect_uri is null
        or create_oauth_authorization_code.redirect_uri = any (c."redirect_uris"))
  ) then
    raise exception 'the client is unknown, can''t use codes, or didn''t register the redirect URI' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  v_grant := "better_supabase"."oauth_grant_for"(create_oauth_authorization_code.user_id,
    create_oauth_authorization_code.client_id, array(select s from unnest(regexp_split_to_array(btrim(coalesce(create_oauth_authorization_code.scope, '')), '\s+')) s where s <> ''),
    coalesce(create_oauth_authorization_code.resource, '{}'));
  insert into "better_supabase"."oauth_authorization_codes" ("code_hash", "client_id", "user_id", "grant_id", "redirect_uri",
    "scope", "resource", "code_challenge", "nonce", "expires_at")
  values (create_oauth_authorization_code.code_hash, create_oauth_authorization_code.client_id,
    create_oauth_authorization_code.user_id, v_grant, create_oauth_authorization_code.redirect_uri,
    coalesce(create_oauth_authorization_code.scope, ''), coalesce(create_oauth_authorization_code.resource, '{}'),
    create_oauth_authorization_code.code_challenge,
    create_oauth_authorization_code.nonce, now() + create_oauth_authorization_code.ttl);
  return jsonb_build_object('grantId', v_grant);
end;
$$;
revoke execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) to service_role;

-- Consumes a code once. code_challenge is S256 of the presented verifier.
-- A code presented twice revokes its grant (RFC 9700 section 4.5).
drop function if exists "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text);
create or replace function "better_supabase"."redeem_oauth_authorization_code"(
  code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code "better_supabase"."oauth_authorization_codes";
  v_grant "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_code from "better_supabase"."oauth_authorization_codes" a
  where a."code_hash" = redeem_oauth_authorization_code.code_hash
  for update;
  if v_code."code_hash" is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_code."consumed_at" is not null then
    update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
    where g."id" = v_code."grant_id" and g."revoked_at" is null
    returning g.* into v_grant;
    if v_grant."id" is not null then
      perform "better_supabase".emit_event('oauth_grant.revoked', jsonb_build_object('grantId', v_grant."id"::text, 'userId', v_grant."user_id"::text, 'clientId', v_grant."client_id"), 'oauth-grants/' || v_grant."id"::text, null, null, 'better-supabase/oauth-server');
  perform better_supabase.audit_event(
    event_type => 'oauth_grant.revoked',
    category => 'access',
    target_type => 'oauth_grant',
    record_id => v_grant."id"::text,
    metadata => jsonb_build_object('grantId', v_grant."id"::text, 'userId', v_grant."user_id"::text, 'clientId', v_grant."client_id"),
    actor_id => v_grant."user_id"
  );
    end if;
    return jsonb_build_object('status', 'invalid', 'replayed', true);
  end if;
  update "better_supabase"."oauth_authorization_codes" a set "consumed_at" = now()
  where a."code_hash" = v_code."code_hash";
  if v_code."expires_at" <= now()
    or v_code."client_id" <> redeem_oauth_authorization_code.client_id
    or v_code."redirect_uri" is distinct from redeem_oauth_authorization_code.redirect_uri
    or v_code."code_challenge" <> redeem_oauth_authorization_code.code_challenge
    or not exists (
      select 1 from "better_supabase"."oauth_grants" g
      where g."id" = v_code."grant_id" and g."revoked_at" is null
    ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- RFC 8707 section 2.2: a token request may narrow the resources of the
  -- code but never widen them.
  if redeem_oauth_authorization_code.resource is not null
    and not redeem_oauth_authorization_code.resource <@ v_code."resource" then
    return jsonb_build_object('status', 'invalid', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_code."user_id", 'clientId', v_code."client_id",
    'grantId', v_code."grant_id", 'scope', v_code."scope", 'nonce', v_code."nonce",
    'resource', to_jsonb(coalesce(redeem_oauth_authorization_code.resource, v_code."resource")));
end;
$$;
revoke execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) to service_role;

-- Starts a device authorization (RFC 8628 section 3.2).
drop function if exists "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer);
create or replace function "better_supabase"."create_oauth_device_code"(
  device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5,
  resource text[] default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_device_code.client_id
      and 'urn:ietf:params:oauth:grant-type:device_code' = any (c."grant_types")
  ) then
    raise exception 'the client is unknown or can''t use the device flow' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  insert into "better_supabase"."oauth_device_codes" ("device_code_hash", "user_code", "client_id", "scope",
    "resource", "poll_interval", "expires_at")
  values (create_oauth_device_code.device_code_hash, create_oauth_device_code.user_code,
    create_oauth_device_code.client_id, coalesce(create_oauth_device_code.scope, ''),
    coalesce(create_oauth_device_code.resource, '{}'),
    coalesce(create_oauth_device_code.poll_interval, 5), now() + create_oauth_device_code.ttl);
  return true;
end;
$$;
revoke execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) to service_role;

-- The pending request behind a user code, for the verification page, or null.
create or replace function "better_supabase"."oauth_device_request"(user_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('clientId', d."client_id", 'scope', d."scope", 'resource', to_jsonb(d."resource"), 'expiresAt', d."expires_at")
    from "better_supabase"."oauth_device_codes" d
    where d."user_code" = oauth_device_request.user_code
      and d."status" = 'pending'
      and d."expires_at" > now()
  );
end;
$$;
revoke execute on function "better_supabase"."oauth_device_request"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_device_request"(text) to service_role;

-- Approves or denies a pending user code for the signed-in user; false when
-- there is no such pending, unexpired code.
create or replace function "better_supabase"."decide_oauth_device_code"(user_code text, user_id uuid, approve boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."user_code" = decide_oauth_device_code.user_code
    and d."status" = 'pending'
    and d."expires_at" > now()
  for update;
  if v_device."device_code_hash" is null then
    return false;
  end if;
  if decide_oauth_device_code.approve then
    v_grant := "better_supabase"."oauth_grant_for"(decide_oauth_device_code.user_id, v_device."client_id",
      array(select s from unnest(regexp_split_to_array(btrim(coalesce(v_device."scope", '')), '\s+')) s where s <> ''), v_device."resource");
  end if;
  update "better_supabase"."oauth_device_codes" d set
    "status" = case when decide_oauth_device_code.approve then 'approved' else 'denied' end,
    "user_id" = decide_oauth_device_code.user_id,
    "grant_id" = v_grant
  where d."device_code_hash" = v_device."device_code_hash";
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) to service_role;

-- A token request's poll (RFC 8628 section 3.5): pending, slow_down,
-- access_denied, expired_token, invalid_grant, or ok once.
drop function if exists "better_supabase"."poll_oauth_device_code"(text, text);
create or replace function "better_supabase"."poll_oauth_device_code"(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."device_code_hash" = poll_oauth_device_code.device_code_hash
  for update;
  if v_device."device_code_hash" is null
    or v_device."client_id" <> poll_oauth_device_code.client_id
    or v_device."consumed_at" is not null then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if v_device."expires_at" <= now() then
    return jsonb_build_object('status', 'expired_token');
  end if;
  if v_device."status" = 'denied' then
    update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'access_denied');
  end if;
  if v_device."status" = 'pending' then
    if v_device."last_polled_at" is not null
      and v_device."last_polled_at" + make_interval(secs => v_device."poll_interval") > now() then
      update "better_supabase"."oauth_device_codes" d set "poll_interval" = least(d."poll_interval" + 5, 300), "last_polled_at" = now()
      where d."device_code_hash" = v_device."device_code_hash";
      return jsonb_build_object('status', 'slow_down', 'interval', least(v_device."poll_interval" + 5, 300));
    end if;
    update "better_supabase"."oauth_device_codes" d set "last_polled_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'authorization_pending', 'interval', v_device."poll_interval");
  end if;
  update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
  where d."device_code_hash" = v_device."device_code_hash";
  if not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id" = v_device."grant_id" and g."revoked_at" is null
  ) then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if poll_oauth_device_code.resource is not null
    and not poll_oauth_device_code.resource <@ v_device."resource" then
    return jsonb_build_object('status', 'invalid_grant', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_device."user_id", 'clientId', v_device."client_id",
    'grantId', v_device."grant_id", 'scope', v_device."scope",
    'resource', to_jsonb(coalesce(poll_oauth_device_code.resource, v_device."resource")));
end;
$$;
revoke execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) to service_role;

-- A user's grants, newest first; revoked ones only with include_revoked.
create or replace function "better_supabase"."list_oauth_grants"(user_id uuid, include_revoked boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = list_oauth_grants.user_id
      and (list_oauth_grants.include_revoked or g."revoked_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) to service_role;

-- Revokes a grant, which ends every token and code issued under it.
create or replace function "better_supabase"."revoke_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_oauth_grant.grant_id and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('oauth_grant.revoked', jsonb_build_object('grantId', v_row."id"::text, 'userId', v_row."user_id"::text, 'clientId', v_row."client_id"), 'oauth-grants/' || v_row."id"::text, null, null, 'better-supabase/oauth-server');
  perform better_supabase.audit_event(
    event_type => 'oauth_grant.revoked',
    category => 'access',
    target_type => 'oauth_grant',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('grantId', v_row."id"::text, 'userId', v_row."user_id"::text, 'clientId', v_row."client_id"),
    actor_id => v_row."user_id"
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_grant"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_grant"(uuid) to service_role;

-- The signed-in user's active grants, for a "connected apps" page.
create or replace function "better_supabase"."my_oauth_grants"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = (select auth.uid())
      and g."revoked_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."my_oauth_grants"() from public, anon;
grant execute on function "better_supabase"."my_oauth_grants"() to authenticated, service_role;

-- Revokes one of the signed-in user's grants; false when it isn't theirs or active.
create or replace function "better_supabase"."revoke_my_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_my_oauth_grant.grant_id
    and g."user_id" = (select auth.uid())
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('oauth_grant.revoked', jsonb_build_object('grantId', v_row."id"::text, 'userId', v_row."user_id"::text, 'clientId', v_row."client_id"), 'oauth-grants/' || v_row."id"::text, null, null, 'better-supabase/oauth-server');
  perform better_supabase.audit_event(
    event_type => 'oauth_grant.revoked',
    category => 'access',
    target_type => 'oauth_grant',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('grantId', v_row."id"::text, 'userId', v_row."user_id"::text, 'clientId', v_row."client_id"),
    actor_id => v_row."user_id"
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) to authenticated, service_role;

-- Adds an access token's jti to the revocation list until it expires.
create or replace function "better_supabase"."revoke_oauth_token"(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_revocations" ("jti", "grant_id", "expires_at")
  values (revoke_oauth_token.jti, revoke_oauth_token.grant_id, revoke_oauth_token.expires_at)
  on conflict ("jti") do update
    set "expires_at" = greatest("better_supabase"."oauth_revocations"."expires_at", excluded."expires_at");
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) to service_role;

-- True when the jti is on the revocation list, or the grant is revoked or
-- gone. A grant id that isn't a uuid counts as gone.
create or replace function "better_supabase"."is_oauth_token_revoked"(jti text, grant_id text default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."oauth_revocations" r where r."jti" = is_oauth_token_revoked.jti) then
    return true;
  end if;
  if is_oauth_token_revoked.grant_id is null then
    return false;
  end if;
  return not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id"::text = is_oauth_token_revoked.grant_id
      and g."revoked_at" is null
  );
end;
$$;
revoke execute on function "better_supabase"."is_oauth_token_revoked"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."is_oauth_token_revoked"(text, text) to service_role;

-- Deletes expired codes, device codes and revocation entries.
create or replace function "better_supabase"."purge_oauth_server"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_authorization_codes" a where a."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_device_codes" d where d."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_revocations" r where r."expires_at" < now();
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke execute on function "better_supabase"."purge_oauth_server"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_oauth_server"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block-data oauth-server
-- @bsb-hash sha256:fab570c8a0c09333723619c92dc55f7398532ffcd876d492a19b0cb2362b9a2f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('oauth-server', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block oauth-server@1 managed
-- @bsb-hash sha256:1d72d0250ef85316877acdc30d51453eae37e8483e8212b73e9ea88dffcc765d
-- Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOAuthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- OAuth 2.1 authorization server storage: registered clients (RFC 7591)
-- with hashed secrets, a user's grant per client, single-use authorization
-- codes bound to a PKCE S256 challenge (RFC 7636), device codes (RFC 8628)
-- and a revocation list of access token jtis. Tokens are issued elsewhere.
create table if not exists "app_private"."oauth_clients" (
  "id" uuid primary key default gen_random_uuid(),
  "client_id" text not null unique check ("client_id" ~ '^[A-Za-z0-9._~-]{8,128}$'),
  "secret_hash" text check ("secret_hash" ~ '^[0-9a-f]{64}$'),
  "registration_token_hash" text check ("registration_token_hash" ~ '^[0-9a-f]{64}$'),
  "client_name" text check (length("client_name") <= 200),
  "redirect_uris" text[] not null default '{}',
  "grant_types" text[] not null default '{authorization_code}'
    check ("grant_types" <@ array['authorization_code', 'refresh_token', 'client_credentials', 'urn:ietf:params:oauth:grant-type:device_code']::text[]),
  "token_endpoint_auth_method" text not null default 'client_secret_basic'
    check ("token_endpoint_auth_method" in ('none', 'client_secret_basic', 'client_secret_post')),
  "scope" text,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("token_endpoint_auth_method" = 'none') = ("secret_hash" is null))
);
create index if not exists oauth_clients_created_by_idx on "app_private"."oauth_clients" ("created_by");
alter table "app_private"."oauth_clients" enable row level security;
revoke all on "app_private"."oauth_clients" from public, anon, authenticated;
grant all on "app_private"."oauth_clients" to service_role;

create table if not exists "app_private"."oauth_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "client_id" text not null references "app_private"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scopes" text[] not null default '{}',
  "resource" text[] not null default '{}',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists oauth_grants_active_idx on "app_private"."oauth_grants" ("user_id", "client_id") where "revoked_at" is null;
create index if not exists oauth_grants_client_idx on "app_private"."oauth_grants" ("client_id");
alter table "app_private"."oauth_grants" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_grants_user_idx on "app_private"."oauth_grants" ("user_id");
alter table "app_private"."oauth_grants" enable row level security;
revoke all on "app_private"."oauth_grants" from public, anon, authenticated;
grant all on "app_private"."oauth_grants" to service_role;

create table if not exists "app_private"."oauth_authorization_codes" (
  "code_hash" text primary key check ("code_hash" ~ '^[0-9a-f]{64}$'),
  "client_id" text not null references "app_private"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "grant_id" uuid not null references "app_private"."oauth_grants" ("id") on delete cascade,
  "redirect_uri" text,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "code_challenge" text not null check ("code_challenge" ~ '^[A-Za-z0-9_-]{43}$'),
  "nonce" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_authorization_codes_expires_idx on "app_private"."oauth_authorization_codes" ("expires_at");
create index if not exists oauth_authorization_codes_grant_idx on "app_private"."oauth_authorization_codes" ("grant_id");
create index if not exists oauth_authorization_codes_client_idx on "app_private"."oauth_authorization_codes" ("client_id");
alter table "app_private"."oauth_authorization_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_authorization_codes_user_idx on "app_private"."oauth_authorization_codes" ("user_id");
alter table "app_private"."oauth_authorization_codes" enable row level security;
revoke all on "app_private"."oauth_authorization_codes" from public, anon, authenticated;
grant all on "app_private"."oauth_authorization_codes" to service_role;

create table if not exists "app_private"."oauth_device_codes" (
  "device_code_hash" text primary key check ("device_code_hash" ~ '^[0-9a-f]{64}$'),
  "user_code" text not null check ("user_code" ~ '^[A-Z0-9]{6,12}$'),
  "client_id" text not null references "app_private"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'denied')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "grant_id" uuid references "app_private"."oauth_grants" ("id") on delete cascade,
  "poll_interval" integer not null default 5 check ("poll_interval" between 1 and 300),
  "last_polled_at" timestamptz,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check (("status" = 'approved') = ("grant_id" is not null))
);
create unique index if not exists oauth_device_codes_user_code_idx on "app_private"."oauth_device_codes" ("user_code") where "status" = 'pending';
create index if not exists oauth_device_codes_expires_idx on "app_private"."oauth_device_codes" ("expires_at");
create index if not exists oauth_device_codes_grant_idx on "app_private"."oauth_device_codes" ("grant_id");
create index if not exists oauth_device_codes_client_idx on "app_private"."oauth_device_codes" ("client_id");
alter table "app_private"."oauth_device_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_device_codes_user_idx on "app_private"."oauth_device_codes" ("user_id");
alter table "app_private"."oauth_device_codes" enable row level security;
revoke all on "app_private"."oauth_device_codes" from public, anon, authenticated;
grant all on "app_private"."oauth_device_codes" to service_role;

create table if not exists "app_private"."oauth_revocations" (
  "jti" text primary key check (length("jti") between 1 and 256),
  "grant_id" uuid,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_revocations_expires_idx on "app_private"."oauth_revocations" ("expires_at");
alter table "app_private"."oauth_revocations" enable row level security;
revoke all on "app_private"."oauth_revocations" from public, anon, authenticated;
grant all on "app_private"."oauth_revocations" to service_role;

-- The user's active grant for the client, widened to the scopes; a new one
-- when there is none. Only the definer functions below call it.
drop function if exists "app_private"."oauth_grant_for"(uuid, text, text[]);
create or replace function "app_private"."oauth_grant_for"(user_id uuid, client_id text, scopes text[], resource text[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "app_private"."oauth_grants" g
  set "scopes" = array(select distinct s from unnest(g."scopes" || oauth_grant_for.scopes) s order by s),
    "resource" = array(select distinct r from unnest(g."resource" || coalesce(oauth_grant_for.resource, '{}')) r order by r),
    "updated_at" = now()
  where g."user_id" = oauth_grant_for.user_id
    and g."client_id" = oauth_grant_for.client_id
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    insert into "app_private"."oauth_grants" ("user_id", "client_id", "scopes", "resource")
    values (oauth_grant_for.user_id, oauth_grant_for.client_id,
      array(select distinct s from unnest(oauth_grant_for.scopes) s order by s),
      array(select distinct r from unnest(coalesce(oauth_grant_for.resource, '{}')) r order by r))
    returning * into v_row;
    null;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "app_private"."oauth_grant_for"(uuid, text, text[], text[]) from public, anon, authenticated, service_role;

-- Registers a client (RFC 7591). The secret and registration token arrive hashed.
create or replace function "app_private"."register_oauth_client"(
  client_id text, secret_hash text, registration_token_hash text, client_name text,
  redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text,
  metadata jsonb, created_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "app_private"."oauth_clients" ("client_id", "secret_hash", "registration_token_hash", "client_name",
    "redirect_uris", "grant_types", "token_endpoint_auth_method", "scope", "metadata", "created_by")
  values (register_oauth_client.client_id, register_oauth_client.secret_hash,
    register_oauth_client.registration_token_hash, register_oauth_client.client_name,
    coalesce(register_oauth_client.redirect_uris, '{}'),
    coalesce(register_oauth_client.grant_types, '{authorization_code}'),
    coalesce(register_oauth_client.token_endpoint_auth_method, 'client_secret_basic'),
    register_oauth_client.scope, coalesce(register_oauth_client.metadata, '{}'::jsonb),
    register_oauth_client.created_by)
  returning * into v_row;
  null;
  return jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "app_private"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) to service_role;

-- A client without its hashes, or null.
create or replace function "app_private"."oauth_client"(client_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at") from "app_private"."oauth_clients" c where c."client_id" = oauth_client.client_id);
end;
$$;
revoke execute on function "app_private"."oauth_client"(text) from public, anon, authenticated;
grant execute on function "app_private"."oauth_client"(text) to service_role;

-- The client when the secret hash matches (null secret for a public client), or null.
create or replace function "app_private"."verify_oauth_client"(client_id text, secret_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at")
    from "app_private"."oauth_clients" c
    where c."client_id" = verify_oauth_client.client_id
      and c."secret_hash" is not distinct from verify_oauth_client.secret_hash
  );
end;
$$;
revoke execute on function "app_private"."verify_oauth_client"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."verify_oauth_client"(text, text) to service_role;

-- Whether the registration access token (RFC 7592) belongs to the client.
create or replace function "app_private"."verify_oauth_registration_token"(client_id text, token_hash text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return exists (
    select 1 from "app_private"."oauth_clients" c
    where c."client_id" = verify_oauth_registration_token.client_id
      and c."registration_token_hash" = verify_oauth_registration_token.token_hash
  );
end;
$$;
revoke execute on function "app_private"."verify_oauth_registration_token"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."verify_oauth_registration_token"(text, text) to service_role;

-- Replaces a client's metadata (RFC 7592); null keeps a value. Null when unknown.
create or replace function "app_private"."update_oauth_client"(
  client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "app_private"."oauth_clients" c set
    "client_name" = coalesce(update_oauth_client.client_name, c."client_name"),
    "redirect_uris" = coalesce(update_oauth_client.redirect_uris, c."redirect_uris"),
    "grant_types" = coalesce(update_oauth_client.grant_types, c."grant_types"),
    "scope" = coalesce(update_oauth_client.scope, c."scope"),
    "metadata" = coalesce(update_oauth_client.metadata, c."metadata"),
    "updated_at" = now()
  where c."client_id" = update_oauth_client.client_id
  returning c.* into v_row;
  return case when v_row."id" is null then null else jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at") end;
end;
$$;
revoke execute on function "app_private"."update_oauth_client"(text, text, text[], text[], text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."update_oauth_client"(text, text, text[], text[], text, jsonb) to service_role;

-- Sets a new secret hash for a confidential client; false when unknown or public.
create or replace function "app_private"."rotate_oauth_client_secret"(client_id text, secret_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "app_private"."oauth_clients" c set "secret_hash" = rotate_oauth_client_secret.secret_hash, "updated_at" = now()
  where c."client_id" = rotate_oauth_client_secret.client_id and c."token_endpoint_auth_method" <> 'none';
  return found;
end;
$$;
revoke execute on function "app_private"."rotate_oauth_client_secret"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."rotate_oauth_client_secret"(text, text) to service_role;

-- Deletes a client with its grants and codes; its tokens fail the grant check.
create or replace function "app_private"."delete_oauth_client"(client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "app_private"."oauth_clients" c where c."client_id" = delete_oauth_client.client_id;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_oauth_client"(text) from public, anon, authenticated;
grant execute on function "app_private"."delete_oauth_client"(text) to service_role;

-- Stores an authorization code after consent, under the user's grant.
drop function if exists "app_private"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text);
create or replace function "app_private"."create_oauth_authorization_code"(
  code_hash text, client_id text, user_id uuid, redirect_uri text, scope text,
  code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "app_private"."oauth_clients" c
    where c."client_id" = create_oauth_authorization_code.client_id
      and 'authorization_code' = any (c."grant_types")
      and (create_oauth_authorization_code.redirect_uri is null
        or create_oauth_authorization_code.redirect_uri = any (c."redirect_uris"))
  ) then
    raise exception 'the client is unknown, can''t use codes, or didn''t register the redirect URI' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  v_grant := "app_private"."oauth_grant_for"(create_oauth_authorization_code.user_id,
    create_oauth_authorization_code.client_id, array(select s from unnest(regexp_split_to_array(btrim(coalesce(create_oauth_authorization_code.scope, '')), '\s+')) s where s <> ''),
    coalesce(create_oauth_authorization_code.resource, '{}'));
  insert into "app_private"."oauth_authorization_codes" ("code_hash", "client_id", "user_id", "grant_id", "redirect_uri",
    "scope", "resource", "code_challenge", "nonce", "expires_at")
  values (create_oauth_authorization_code.code_hash, create_oauth_authorization_code.client_id,
    create_oauth_authorization_code.user_id, v_grant, create_oauth_authorization_code.redirect_uri,
    coalesce(create_oauth_authorization_code.scope, ''), coalesce(create_oauth_authorization_code.resource, '{}'),
    create_oauth_authorization_code.code_challenge,
    create_oauth_authorization_code.nonce, now() + create_oauth_authorization_code.ttl);
  return jsonb_build_object('grantId', v_grant);
end;
$$;
revoke execute on function "app_private"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) from public, anon, authenticated;
grant execute on function "app_private"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) to service_role;

-- Consumes a code once. code_challenge is S256 of the presented verifier.
-- A code presented twice revokes its grant (RFC 9700 section 4.5).
drop function if exists "app_private"."redeem_oauth_authorization_code"(text, text, text, text);
create or replace function "app_private"."redeem_oauth_authorization_code"(
  code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code "app_private"."oauth_authorization_codes";
  v_grant "app_private"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_code from "app_private"."oauth_authorization_codes" a
  where a."code_hash" = redeem_oauth_authorization_code.code_hash
  for update;
  if v_code."code_hash" is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_code."consumed_at" is not null then
    update "app_private"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
    where g."id" = v_code."grant_id" and g."revoked_at" is null
    returning g.* into v_grant;
    if v_grant."id" is not null then
      null;
    end if;
    return jsonb_build_object('status', 'invalid', 'replayed', true);
  end if;
  update "app_private"."oauth_authorization_codes" a set "consumed_at" = now()
  where a."code_hash" = v_code."code_hash";
  if v_code."expires_at" <= now()
    or v_code."client_id" <> redeem_oauth_authorization_code.client_id
    or v_code."redirect_uri" is distinct from redeem_oauth_authorization_code.redirect_uri
    or v_code."code_challenge" <> redeem_oauth_authorization_code.code_challenge
    or not exists (
      select 1 from "app_private"."oauth_grants" g
      where g."id" = v_code."grant_id" and g."revoked_at" is null
    ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- RFC 8707 section 2.2: a token request may narrow the resources of the
  -- code but never widen them.
  if redeem_oauth_authorization_code.resource is not null
    and not redeem_oauth_authorization_code.resource <@ v_code."resource" then
    return jsonb_build_object('status', 'invalid', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_code."user_id", 'clientId', v_code."client_id",
    'grantId', v_code."grant_id", 'scope', v_code."scope", 'nonce', v_code."nonce",
    'resource', to_jsonb(coalesce(redeem_oauth_authorization_code.resource, v_code."resource")));
end;
$$;
revoke execute on function "app_private"."redeem_oauth_authorization_code"(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function "app_private"."redeem_oauth_authorization_code"(text, text, text, text, text[]) to service_role;

-- Starts a device authorization (RFC 8628 section 3.2).
drop function if exists "app_private"."create_oauth_device_code"(text, text, text, text, interval, integer);
create or replace function "app_private"."create_oauth_device_code"(
  device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5,
  resource text[] default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "app_private"."oauth_clients" c
    where c."client_id" = create_oauth_device_code.client_id
      and 'urn:ietf:params:oauth:grant-type:device_code' = any (c."grant_types")
  ) then
    raise exception 'the client is unknown or can''t use the device flow' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  insert into "app_private"."oauth_device_codes" ("device_code_hash", "user_code", "client_id", "scope",
    "resource", "poll_interval", "expires_at")
  values (create_oauth_device_code.device_code_hash, create_oauth_device_code.user_code,
    create_oauth_device_code.client_id, coalesce(create_oauth_device_code.scope, ''),
    coalesce(create_oauth_device_code.resource, '{}'),
    coalesce(create_oauth_device_code.poll_interval, 5), now() + create_oauth_device_code.ttl);
  return true;
end;
$$;
revoke execute on function "app_private"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) from public, anon, authenticated;
grant execute on function "app_private"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) to service_role;

-- The pending request behind a user code, for the verification page, or null.
create or replace function "app_private"."oauth_device_request"(user_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('clientId', d."client_id", 'scope', d."scope", 'resource', to_jsonb(d."resource"), 'expiresAt', d."expires_at")
    from "app_private"."oauth_device_codes" d
    where d."user_code" = oauth_device_request.user_code
      and d."status" = 'pending'
      and d."expires_at" > now()
  );
end;
$$;
revoke execute on function "app_private"."oauth_device_request"(text) from public, anon, authenticated;
grant execute on function "app_private"."oauth_device_request"(text) to service_role;

-- Approves or denies a pending user code for the signed-in user; false when
-- there is no such pending, unexpired code.
create or replace function "app_private"."decide_oauth_device_code"(user_code text, user_id uuid, approve boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "app_private"."oauth_device_codes";
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "app_private"."oauth_device_codes" d
  where d."user_code" = decide_oauth_device_code.user_code
    and d."status" = 'pending'
    and d."expires_at" > now()
  for update;
  if v_device."device_code_hash" is null then
    return false;
  end if;
  if decide_oauth_device_code.approve then
    v_grant := "app_private"."oauth_grant_for"(decide_oauth_device_code.user_id, v_device."client_id",
      array(select s from unnest(regexp_split_to_array(btrim(coalesce(v_device."scope", '')), '\s+')) s where s <> ''), v_device."resource");
  end if;
  update "app_private"."oauth_device_codes" d set
    "status" = case when decide_oauth_device_code.approve then 'approved' else 'denied' end,
    "user_id" = decide_oauth_device_code.user_id,
    "grant_id" = v_grant
  where d."device_code_hash" = v_device."device_code_hash";
  return true;
end;
$$;
revoke execute on function "app_private"."decide_oauth_device_code"(text, uuid, boolean) from public, anon, authenticated;
grant execute on function "app_private"."decide_oauth_device_code"(text, uuid, boolean) to service_role;

-- A token request's poll (RFC 8628 section 3.5): pending, slow_down,
-- access_denied, expired_token, invalid_grant, or ok once.
drop function if exists "app_private"."poll_oauth_device_code"(text, text);
create or replace function "app_private"."poll_oauth_device_code"(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "app_private"."oauth_device_codes";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "app_private"."oauth_device_codes" d
  where d."device_code_hash" = poll_oauth_device_code.device_code_hash
  for update;
  if v_device."device_code_hash" is null
    or v_device."client_id" <> poll_oauth_device_code.client_id
    or v_device."consumed_at" is not null then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if v_device."expires_at" <= now() then
    return jsonb_build_object('status', 'expired_token');
  end if;
  if v_device."status" = 'denied' then
    update "app_private"."oauth_device_codes" d set "consumed_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'access_denied');
  end if;
  if v_device."status" = 'pending' then
    if v_device."last_polled_at" is not null
      and v_device."last_polled_at" + make_interval(secs => v_device."poll_interval") > now() then
      update "app_private"."oauth_device_codes" d set "poll_interval" = least(d."poll_interval" + 5, 300), "last_polled_at" = now()
      where d."device_code_hash" = v_device."device_code_hash";
      return jsonb_build_object('status', 'slow_down', 'interval', least(v_device."poll_interval" + 5, 300));
    end if;
    update "app_private"."oauth_device_codes" d set "last_polled_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'authorization_pending', 'interval', v_device."poll_interval");
  end if;
  update "app_private"."oauth_device_codes" d set "consumed_at" = now()
  where d."device_code_hash" = v_device."device_code_hash";
  if not exists (
    select 1 from "app_private"."oauth_grants" g
    where g."id" = v_device."grant_id" and g."revoked_at" is null
  ) then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if poll_oauth_device_code.resource is not null
    and not poll_oauth_device_code.resource <@ v_device."resource" then
    return jsonb_build_object('status', 'invalid_grant', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_device."user_id", 'clientId', v_device."client_id",
    'grantId', v_device."grant_id", 'scope', v_device."scope",
    'resource', to_jsonb(coalesce(poll_oauth_device_code.resource, v_device."resource")));
end;
$$;
revoke execute on function "app_private"."poll_oauth_device_code"(text, text, text[]) from public, anon, authenticated;
grant execute on function "app_private"."poll_oauth_device_code"(text, text, text[]) to service_role;

-- A user's grants, newest first; revoked ones only with include_revoked.
create or replace function "app_private"."list_oauth_grants"(user_id uuid, include_revoked boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "app_private"."oauth_grants" g
    join "app_private"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = list_oauth_grants.user_id
      and (list_oauth_grants.include_revoked or g."revoked_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_oauth_grants"(uuid, boolean) from public, anon, authenticated;
grant execute on function "app_private"."list_oauth_grants"(uuid, boolean) to service_role;

-- Revokes a grant, which ends every token and code issued under it.
create or replace function "app_private"."revoke_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "app_private"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_oauth_grant.grant_id and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."revoke_oauth_grant"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."revoke_oauth_grant"(uuid) to service_role;

-- The signed-in user's active grants, for a "connected apps" page.
create or replace function "app_private"."my_oauth_grants"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "app_private"."oauth_grants" g
    join "app_private"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = (select auth.uid())
      and g."revoked_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."my_oauth_grants"() from public, anon;
grant execute on function "app_private"."my_oauth_grants"() to authenticated, service_role;

-- Revokes one of the signed-in user's grants; false when it isn't theirs or active.
create or replace function "app_private"."revoke_my_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."oauth_grants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_my_oauth_grant.grant_id
    and g."user_id" = (select auth.uid())
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."revoke_my_oauth_grant"(uuid) from public, anon;
grant execute on function "app_private"."revoke_my_oauth_grant"(uuid) to authenticated, service_role;

-- Adds an access token's jti to the revocation list until it expires.
create or replace function "app_private"."revoke_oauth_token"(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "app_private"."oauth_revocations" ("jti", "grant_id", "expires_at")
  values (revoke_oauth_token.jti, revoke_oauth_token.grant_id, revoke_oauth_token.expires_at)
  on conflict ("jti") do update
    set "expires_at" = greatest("app_private"."oauth_revocations"."expires_at", excluded."expires_at");
  return true;
end;
$$;
revoke execute on function "app_private"."revoke_oauth_token"(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "app_private"."revoke_oauth_token"(text, timestamptz, uuid) to service_role;

-- True when the jti is on the revocation list, or the grant is revoked or
-- gone. A grant id that isn't a uuid counts as gone.
create or replace function "app_private"."is_oauth_token_revoked"(jti text, grant_id text default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if exists (select 1 from "app_private"."oauth_revocations" r where r."jti" = is_oauth_token_revoked.jti) then
    return true;
  end if;
  if is_oauth_token_revoked.grant_id is null then
    return false;
  end if;
  return not exists (
    select 1 from "app_private"."oauth_grants" g
    where g."id"::text = is_oauth_token_revoked.grant_id
      and g."revoked_at" is null
  );
end;
$$;
revoke execute on function "app_private"."is_oauth_token_revoked"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."is_oauth_token_revoked"(text, text) to service_role;

-- Deletes expired codes, device codes and revocation entries.
create or replace function "app_private"."purge_oauth_server"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "app_private"."oauth_authorization_codes" a where a."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "app_private"."oauth_device_codes" d where d."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "app_private"."oauth_revocations" r where r."expires_at" < now();
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke execute on function "app_private"."purge_oauth_server"() from public, anon, authenticated;
grant execute on function "app_private"."purge_oauth_server"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block-data oauth-server
-- @bsb-hash sha256:fab570c8a0c09333723619c92dc55f7398532ffcd876d492a19b0cb2362b9a2f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('oauth-server', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block oauth-server@1 managed
-- @bsb-hash sha256:92b5f411594edc0e98dd57a73e4a13bb44b431746feec8ab9cd3397b96d1f998
-- Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOAuthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- OAuth 2.1 authorization server storage: registered clients (RFC 7591)
-- with hashed secrets, a user's grant per client, single-use authorization
-- codes bound to a PKCE S256 challenge (RFC 7636), device codes (RFC 8628)
-- and a revocation list of access token jtis. Tokens are issued elsewhere.
create table if not exists "better_supabase"."oauth_clients" (
  "id" uuid primary key default gen_random_uuid(),
  "client_id" text not null unique check ("client_id" ~ '^[A-Za-z0-9._~-]{8,128}$'),
  "secret_hash" text check ("secret_hash" ~ '^[0-9a-f]{64}$'),
  "registration_token_hash" text check ("registration_token_hash" ~ '^[0-9a-f]{64}$'),
  "client_name" text check (length("client_name") <= 200),
  "redirect_uris" text[] not null default '{}',
  "grant_types" text[] not null default '{authorization_code}'
    check ("grant_types" <@ array['authorization_code', 'refresh_token', 'client_credentials', 'urn:ietf:params:oauth:grant-type:device_code']::text[]),
  "token_endpoint_auth_method" text not null default 'client_secret_basic'
    check ("token_endpoint_auth_method" in ('none', 'client_secret_basic', 'client_secret_post')),
  "scope" text,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("token_endpoint_auth_method" = 'none') = ("secret_hash" is null))
);
create index if not exists oauth_clients_created_by_idx on "better_supabase"."oauth_clients" ("created_by");
alter table "better_supabase"."oauth_clients" enable row level security;
revoke all on "better_supabase"."oauth_clients" from public, anon, authenticated;
grant all on "better_supabase"."oauth_clients" to service_role;

create table if not exists "better_supabase"."oauth_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scopes" text[] not null default '{}',
  "resource" text[] not null default '{}',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists oauth_grants_active_idx on "better_supabase"."oauth_grants" ("user_id", "client_id") where "revoked_at" is null;
create index if not exists oauth_grants_client_idx on "better_supabase"."oauth_grants" ("client_id");
alter table "better_supabase"."oauth_grants" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_grants_user_idx on "better_supabase"."oauth_grants" ("user_id");
alter table "better_supabase"."oauth_grants" enable row level security;
revoke all on "better_supabase"."oauth_grants" from public, anon, authenticated;
grant all on "better_supabase"."oauth_grants" to service_role;

create table if not exists "better_supabase"."oauth_authorization_codes" (
  "code_hash" text primary key check ("code_hash" ~ '^[0-9a-f]{64}$'),
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "grant_id" uuid not null references "better_supabase"."oauth_grants" ("id") on delete cascade,
  "redirect_uri" text,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "code_challenge" text not null check ("code_challenge" ~ '^[A-Za-z0-9_-]{43}$'),
  "nonce" text,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_authorization_codes_expires_idx on "better_supabase"."oauth_authorization_codes" ("expires_at");
create index if not exists oauth_authorization_codes_grant_idx on "better_supabase"."oauth_authorization_codes" ("grant_id");
create index if not exists oauth_authorization_codes_client_idx on "better_supabase"."oauth_authorization_codes" ("client_id");
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_authorization_codes_user_idx on "better_supabase"."oauth_authorization_codes" ("user_id");
alter table "better_supabase"."oauth_authorization_codes" enable row level security;
revoke all on "better_supabase"."oauth_authorization_codes" from public, anon, authenticated;
grant all on "better_supabase"."oauth_authorization_codes" to service_role;

create table if not exists "better_supabase"."oauth_device_codes" (
  "device_code_hash" text primary key check ("device_code_hash" ~ '^[0-9a-f]{64}$'),
  "user_code" text not null check ("user_code" ~ '^[A-Z0-9]{6,12}$'),
  "client_id" text not null references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade,
  "scope" text not null default '',
  "resource" text[] not null default '{}',
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'denied')),
  "user_id" uuid references auth.users (id) on delete cascade,
  "grant_id" uuid references "better_supabase"."oauth_grants" ("id") on delete cascade,
  "poll_interval" integer not null default 5 check ("poll_interval" between 1 and 300),
  "last_polled_at" timestamptz,
  "expires_at" timestamptz not null,
  "consumed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check (("status" = 'approved') = ("grant_id" is not null))
);
create unique index if not exists oauth_device_codes_user_code_idx on "better_supabase"."oauth_device_codes" ("user_code") where "status" = 'pending';
create index if not exists oauth_device_codes_expires_idx on "better_supabase"."oauth_device_codes" ("expires_at");
create index if not exists oauth_device_codes_grant_idx on "better_supabase"."oauth_device_codes" ("grant_id");
create index if not exists oauth_device_codes_client_idx on "better_supabase"."oauth_device_codes" ("client_id");
alter table "better_supabase"."oauth_device_codes" add column if not exists "resource" text[] not null default '{}';
create index if not exists oauth_device_codes_user_idx on "better_supabase"."oauth_device_codes" ("user_id");
alter table "better_supabase"."oauth_device_codes" enable row level security;
revoke all on "better_supabase"."oauth_device_codes" from public, anon, authenticated;
grant all on "better_supabase"."oauth_device_codes" to service_role;

create table if not exists "better_supabase"."oauth_revocations" (
  "jti" text primary key check (length("jti") between 1 and 256),
  "grant_id" uuid,
  "expires_at" timestamptz not null,
  "created_at" timestamptz not null default now()
);
create index if not exists oauth_revocations_expires_idx on "better_supabase"."oauth_revocations" ("expires_at");
alter table "better_supabase"."oauth_revocations" enable row level security;
revoke all on "better_supabase"."oauth_revocations" from public, anon, authenticated;
grant all on "better_supabase"."oauth_revocations" to service_role;

-- The user's active grant for the client, widened to the scopes; a new one
-- when there is none. Only the definer functions below call it.
drop function if exists "better_supabase"."oauth_grant_for"(uuid, text, text[]);
create or replace function "better_supabase"."oauth_grant_for"(user_id uuid, client_id text, scopes text[], resource text[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g
  set "scopes" = array(select distinct s from unnest(g."scopes" || oauth_grant_for.scopes) s order by s),
    "resource" = array(select distinct r from unnest(g."resource" || coalesce(oauth_grant_for.resource, '{}')) r order by r),
    "updated_at" = now()
  where g."user_id" = oauth_grant_for.user_id
    and g."client_id" = oauth_grant_for.client_id
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    insert into "better_supabase"."oauth_grants" ("user_id", "client_id", "scopes", "resource")
    values (oauth_grant_for.user_id, oauth_grant_for.client_id,
      array(select distinct s from unnest(oauth_grant_for.scopes) s order by s),
      array(select distinct r from unnest(coalesce(oauth_grant_for.resource, '{}')) r order by r))
    returning * into v_row;
    null;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."oauth_grant_for"(uuid, text, text[], text[]) from public, anon, authenticated, service_role;

-- Registers a client (RFC 7591). The secret and registration token arrive hashed.
create or replace function "better_supabase"."register_oauth_client"(
  client_id text, secret_hash text, registration_token_hash text, client_name text,
  redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text,
  metadata jsonb, created_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_clients" ("client_id", "secret_hash", "registration_token_hash", "client_name",
    "redirect_uris", "grant_types", "token_endpoint_auth_method", "scope", "metadata", "created_by")
  values (register_oauth_client.client_id, register_oauth_client.secret_hash,
    register_oauth_client.registration_token_hash, register_oauth_client.client_name,
    coalesce(register_oauth_client.redirect_uris, '{}'),
    coalesce(register_oauth_client.grant_types, '{authorization_code}'),
    coalesce(register_oauth_client.token_endpoint_auth_method, 'client_secret_basic'),
    register_oauth_client.scope, coalesce(register_oauth_client.metadata, '{}'::jsonb),
    register_oauth_client.created_by)
  returning * into v_row;
  null;
  return jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) to service_role;

-- A client without its hashes, or null.
create or replace function "better_supabase"."oauth_client"(client_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at") from "better_supabase"."oauth_clients" c where c."client_id" = oauth_client.client_id);
end;
$$;
revoke execute on function "better_supabase"."oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_client"(text) to service_role;

-- The client when the secret hash matches (null secret for a public client), or null.
create or replace function "better_supabase"."verify_oauth_client"(client_id text, secret_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at")
    from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_client.client_id
      and c."secret_hash" is not distinct from verify_oauth_client.secret_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_client"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_client"(text, text) to service_role;

-- Whether the registration access token (RFC 7592) belongs to the client.
create or replace function "better_supabase"."verify_oauth_registration_token"(client_id text, token_hash text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_registration_token.client_id
      and c."registration_token_hash" = verify_oauth_registration_token.token_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_registration_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_registration_token"(text, text) to service_role;

-- Replaces a client's metadata (RFC 7592); null keeps a value. Null when unknown.
create or replace function "better_supabase"."update_oauth_client"(
  client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set
    "client_name" = coalesce(update_oauth_client.client_name, c."client_name"),
    "redirect_uris" = coalesce(update_oauth_client.redirect_uris, c."redirect_uris"),
    "grant_types" = coalesce(update_oauth_client.grant_types, c."grant_types"),
    "scope" = coalesce(update_oauth_client.scope, c."scope"),
    "metadata" = coalesce(update_oauth_client.metadata, c."metadata"),
    "updated_at" = now()
  where c."client_id" = update_oauth_client.client_id
  returning c.* into v_row;
  return case when v_row."id" is null then null else jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at") end;
end;
$$;
revoke execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) to service_role;

-- Sets a new secret hash for a confidential client; false when unknown or public.
create or replace function "better_supabase"."rotate_oauth_client_secret"(client_id text, secret_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set "secret_hash" = rotate_oauth_client_secret.secret_hash, "updated_at" = now()
  where c."client_id" = rotate_oauth_client_secret.client_id and c."token_endpoint_auth_method" <> 'none';
  return found;
end;
$$;
revoke execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) to service_role;

-- Deletes a client with its grants and codes; its tokens fail the grant check.
create or replace function "better_supabase"."delete_oauth_client"(client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_clients" c where c."client_id" = delete_oauth_client.client_id;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_oauth_client"(text) to service_role;

-- Stores an authorization code after consent, under the user's grant.
drop function if exists "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text);
create or replace function "better_supabase"."create_oauth_authorization_code"(
  code_hash text, client_id text, user_id uuid, redirect_uri text, scope text,
  code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_authorization_code.client_id
      and 'authorization_code' = any (c."grant_types")
      and (create_oauth_authorization_code.redirect_uri is null
        or create_oauth_authorization_code.redirect_uri = any (c."redirect_uris"))
  ) then
    raise exception 'the client is unknown, can''t use codes, or didn''t register the redirect URI' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  v_grant := "better_supabase"."oauth_grant_for"(create_oauth_authorization_code.user_id,
    create_oauth_authorization_code.client_id, array(select s from unnest(regexp_split_to_array(btrim(coalesce(create_oauth_authorization_code.scope, '')), '\s+')) s where s <> ''),
    coalesce(create_oauth_authorization_code.resource, '{}'));
  insert into "better_supabase"."oauth_authorization_codes" ("code_hash", "client_id", "user_id", "grant_id", "redirect_uri",
    "scope", "resource", "code_challenge", "nonce", "expires_at")
  values (create_oauth_authorization_code.code_hash, create_oauth_authorization_code.client_id,
    create_oauth_authorization_code.user_id, v_grant, create_oauth_authorization_code.redirect_uri,
    coalesce(create_oauth_authorization_code.scope, ''), coalesce(create_oauth_authorization_code.resource, '{}'),
    create_oauth_authorization_code.code_challenge,
    create_oauth_authorization_code.nonce, now() + create_oauth_authorization_code.ttl);
  return jsonb_build_object('grantId', v_grant);
end;
$$;
revoke execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) to service_role;

-- Consumes a code once. code_challenge is S256 of the presented verifier.
-- A code presented twice revokes its grant (RFC 9700 section 4.5).
drop function if exists "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text);
create or replace function "better_supabase"."redeem_oauth_authorization_code"(
  code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code "better_supabase"."oauth_authorization_codes";
  v_grant "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_code from "better_supabase"."oauth_authorization_codes" a
  where a."code_hash" = redeem_oauth_authorization_code.code_hash
  for update;
  if v_code."code_hash" is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_code."consumed_at" is not null then
    update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
    where g."id" = v_code."grant_id" and g."revoked_at" is null
    returning g.* into v_grant;
    if v_grant."id" is not null then
      null;
    end if;
    return jsonb_build_object('status', 'invalid', 'replayed', true);
  end if;
  update "better_supabase"."oauth_authorization_codes" a set "consumed_at" = now()
  where a."code_hash" = v_code."code_hash";
  if v_code."expires_at" <= now()
    or v_code."client_id" <> redeem_oauth_authorization_code.client_id
    or v_code."redirect_uri" is distinct from redeem_oauth_authorization_code.redirect_uri
    or v_code."code_challenge" <> redeem_oauth_authorization_code.code_challenge
    or not exists (
      select 1 from "better_supabase"."oauth_grants" g
      where g."id" = v_code."grant_id" and g."revoked_at" is null
    ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- RFC 8707 section 2.2: a token request may narrow the resources of the
  -- code but never widen them.
  if redeem_oauth_authorization_code.resource is not null
    and not redeem_oauth_authorization_code.resource <@ v_code."resource" then
    return jsonb_build_object('status', 'invalid', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_code."user_id", 'clientId', v_code."client_id",
    'grantId', v_code."grant_id", 'scope', v_code."scope", 'nonce', v_code."nonce",
    'resource', to_jsonb(coalesce(redeem_oauth_authorization_code.resource, v_code."resource")));
end;
$$;
revoke execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) to service_role;

-- Starts a device authorization (RFC 8628 section 3.2).
drop function if exists "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer);
create or replace function "better_supabase"."create_oauth_device_code"(
  device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5,
  resource text[] default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_device_code.client_id
      and 'urn:ietf:params:oauth:grant-type:device_code' = any (c."grant_types")
  ) then
    raise exception 'the client is unknown or can''t use the device flow' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  insert into "better_supabase"."oauth_device_codes" ("device_code_hash", "user_code", "client_id", "scope",
    "resource", "poll_interval", "expires_at")
  values (create_oauth_device_code.device_code_hash, create_oauth_device_code.user_code,
    create_oauth_device_code.client_id, coalesce(create_oauth_device_code.scope, ''),
    coalesce(create_oauth_device_code.resource, '{}'),
    coalesce(create_oauth_device_code.poll_interval, 5), now() + create_oauth_device_code.ttl);
  return true;
end;
$$;
revoke execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) to service_role;

-- The pending request behind a user code, for the verification page, or null.
create or replace function "better_supabase"."oauth_device_request"(user_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('clientId', d."client_id", 'scope', d."scope", 'resource', to_jsonb(d."resource"), 'expiresAt', d."expires_at")
    from "better_supabase"."oauth_device_codes" d
    where d."user_code" = oauth_device_request.user_code
      and d."status" = 'pending'
      and d."expires_at" > now()
  );
end;
$$;
revoke execute on function "better_supabase"."oauth_device_request"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_device_request"(text) to service_role;

-- Approves or denies a pending user code for the signed-in user; false when
-- there is no such pending, unexpired code.
create or replace function "better_supabase"."decide_oauth_device_code"(user_code text, user_id uuid, approve boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."user_code" = decide_oauth_device_code.user_code
    and d."status" = 'pending'
    and d."expires_at" > now()
  for update;
  if v_device."device_code_hash" is null then
    return false;
  end if;
  if decide_oauth_device_code.approve then
    v_grant := "better_supabase"."oauth_grant_for"(decide_oauth_device_code.user_id, v_device."client_id",
      array(select s from unnest(regexp_split_to_array(btrim(coalesce(v_device."scope", '')), '\s+')) s where s <> ''), v_device."resource");
  end if;
  update "better_supabase"."oauth_device_codes" d set
    "status" = case when decide_oauth_device_code.approve then 'approved' else 'denied' end,
    "user_id" = decide_oauth_device_code.user_id,
    "grant_id" = v_grant
  where d."device_code_hash" = v_device."device_code_hash";
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) to service_role;

-- A token request's poll (RFC 8628 section 3.5): pending, slow_down,
-- access_denied, expired_token, invalid_grant, or ok once.
drop function if exists "better_supabase"."poll_oauth_device_code"(text, text);
create or replace function "better_supabase"."poll_oauth_device_code"(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."device_code_hash" = poll_oauth_device_code.device_code_hash
  for update;
  if v_device."device_code_hash" is null
    or v_device."client_id" <> poll_oauth_device_code.client_id
    or v_device."consumed_at" is not null then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if v_device."expires_at" <= now() then
    return jsonb_build_object('status', 'expired_token');
  end if;
  if v_device."status" = 'denied' then
    update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'access_denied');
  end if;
  if v_device."status" = 'pending' then
    if v_device."last_polled_at" is not null
      and v_device."last_polled_at" + make_interval(secs => v_device."poll_interval") > now() then
      update "better_supabase"."oauth_device_codes" d set "poll_interval" = least(d."poll_interval" + 5, 300), "last_polled_at" = now()
      where d."device_code_hash" = v_device."device_code_hash";
      return jsonb_build_object('status', 'slow_down', 'interval', least(v_device."poll_interval" + 5, 300));
    end if;
    update "better_supabase"."oauth_device_codes" d set "last_polled_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'authorization_pending', 'interval', v_device."poll_interval");
  end if;
  update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
  where d."device_code_hash" = v_device."device_code_hash";
  if not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id" = v_device."grant_id" and g."revoked_at" is null
  ) then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if poll_oauth_device_code.resource is not null
    and not poll_oauth_device_code.resource <@ v_device."resource" then
    return jsonb_build_object('status', 'invalid_grant', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_device."user_id", 'clientId', v_device."client_id",
    'grantId', v_device."grant_id", 'scope', v_device."scope",
    'resource', to_jsonb(coalesce(poll_oauth_device_code.resource, v_device."resource")));
end;
$$;
revoke execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) to service_role;

-- A user's grants, newest first; revoked ones only with include_revoked.
create or replace function "better_supabase"."list_oauth_grants"(user_id uuid, include_revoked boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = list_oauth_grants.user_id
      and (list_oauth_grants.include_revoked or g."revoked_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) to service_role;

-- Revokes a grant, which ends every token and code issued under it.
create or replace function "better_supabase"."revoke_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_oauth_grant.grant_id and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_grant"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_grant"(uuid) to service_role;

-- The signed-in user's active grants, for a "connected apps" page.
create or replace function "better_supabase"."my_oauth_grants"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = (select auth.uid())
      and g."revoked_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."my_oauth_grants"() from public, anon;
grant execute on function "better_supabase"."my_oauth_grants"() to authenticated, service_role;

-- Revokes one of the signed-in user's grants; false when it isn't theirs or active.
create or replace function "better_supabase"."revoke_my_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_my_oauth_grant.grant_id
    and g."user_id" = (select auth.uid())
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) to authenticated, service_role;

-- Adds an access token's jti to the revocation list until it expires.
create or replace function "better_supabase"."revoke_oauth_token"(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_revocations" ("jti", "grant_id", "expires_at")
  values (revoke_oauth_token.jti, revoke_oauth_token.grant_id, revoke_oauth_token.expires_at)
  on conflict ("jti") do update
    set "expires_at" = greatest("better_supabase"."oauth_revocations"."expires_at", excluded."expires_at");
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) to service_role;

-- True when the jti is on the revocation list, or the grant is revoked or
-- gone. A grant id that isn't a uuid counts as gone.
create or replace function "better_supabase"."is_oauth_token_revoked"(jti text, grant_id text default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."oauth_revocations" r where r."jti" = is_oauth_token_revoked.jti) then
    return true;
  end if;
  if is_oauth_token_revoked.grant_id is null then
    return false;
  end if;
  return not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id"::text = is_oauth_token_revoked.grant_id
      and g."revoked_at" is null
  );
end;
$$;
revoke execute on function "better_supabase"."is_oauth_token_revoked"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."is_oauth_token_revoked"(text, text) to service_role;

-- Deletes expired codes, device codes and revocation entries.
create or replace function "better_supabase"."purge_oauth_server"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_authorization_codes" a where a."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_device_codes" d where d."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_revocations" r where r."expires_at" < now();
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke execute on function "better_supabase"."purge_oauth_server"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_oauth_server"() to service_role;

-- blocks.oauth-server.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text);
drop function if exists "api"."redeem_oauth_authorization_code"(text, text, text, text);
drop function if exists "api"."create_oauth_device_code"(text, text, text, text, interval, integer);
drop function if exists "api"."poll_oauth_device_code"(text, text);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."register_oauth_client"(client_id text, secret_hash text, registration_token_hash text, client_name text, redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text, metadata jsonb, created_by uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_oauth_client"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "api"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) to service_role;

create or replace function "api"."oauth_client"(client_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."oauth_client"($1) $$;
revoke execute on function "api"."oauth_client"(text) from public, anon, authenticated;
grant execute on function "api"."oauth_client"(text) to service_role;

create or replace function "api"."verify_oauth_client"(client_id text, secret_hash text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."verify_oauth_client"($1, $2) $$;
revoke execute on function "api"."verify_oauth_client"(text, text) from public, anon, authenticated;
grant execute on function "api"."verify_oauth_client"(text, text) to service_role;

create or replace function "api"."verify_oauth_registration_token"(client_id text, token_hash text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."verify_oauth_registration_token"($1, $2) $$;
revoke execute on function "api"."verify_oauth_registration_token"(text, text) from public, anon, authenticated;
grant execute on function "api"."verify_oauth_registration_token"(text, text) to service_role;

create or replace function "api"."update_oauth_client"(client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_oauth_client"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."update_oauth_client"(text, text, text[], text[], text, jsonb) from public, anon, authenticated;
grant execute on function "api"."update_oauth_client"(text, text, text[], text[], text, jsonb) to service_role;

create or replace function "api"."rotate_oauth_client_secret"(client_id text, secret_hash text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rotate_oauth_client_secret"($1, $2) $$;
revoke execute on function "api"."rotate_oauth_client_secret"(text, text) from public, anon, authenticated;
grant execute on function "api"."rotate_oauth_client_secret"(text, text) to service_role;

create or replace function "api"."delete_oauth_client"(client_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_oauth_client"($1) $$;
revoke execute on function "api"."delete_oauth_client"(text) from public, anon, authenticated;
grant execute on function "api"."delete_oauth_client"(text) to service_role;

create or replace function "api"."create_oauth_authorization_code"(code_hash text, client_id text, user_id uuid, redirect_uri text, scope text, code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_oauth_authorization_code"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) from public, anon, authenticated;
grant execute on function "api"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) to service_role;

create or replace function "api"."redeem_oauth_authorization_code"(code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."redeem_oauth_authorization_code"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."redeem_oauth_authorization_code"(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function "api"."redeem_oauth_authorization_code"(text, text, text, text, text[]) to service_role;

create or replace function "api"."create_oauth_device_code"(device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5, resource text[] default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_oauth_device_code"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) from public, anon, authenticated;
grant execute on function "api"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) to service_role;

create or replace function "api"."oauth_device_request"(user_code text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."oauth_device_request"($1) $$;
revoke execute on function "api"."oauth_device_request"(text) from public, anon, authenticated;
grant execute on function "api"."oauth_device_request"(text) to service_role;

create or replace function "api"."decide_oauth_device_code"(user_code text, user_id uuid, approve boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_oauth_device_code"($1, $2, $3) $$;
revoke execute on function "api"."decide_oauth_device_code"(text, uuid, boolean) from public, anon, authenticated;
grant execute on function "api"."decide_oauth_device_code"(text, uuid, boolean) to service_role;

create or replace function "api"."poll_oauth_device_code"(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."poll_oauth_device_code"($1, $2, $3) $$;
revoke execute on function "api"."poll_oauth_device_code"(text, text, text[]) from public, anon, authenticated;
grant execute on function "api"."poll_oauth_device_code"(text, text, text[]) to service_role;

create or replace function "api"."list_oauth_grants"(user_id uuid, include_revoked boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_oauth_grants"($1, $2) $$;
revoke execute on function "api"."list_oauth_grants"(uuid, boolean) from public, anon, authenticated;
grant execute on function "api"."list_oauth_grants"(uuid, boolean) to service_role;

create or replace function "api"."revoke_oauth_grant"(grant_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_oauth_grant"($1) $$;
revoke execute on function "api"."revoke_oauth_grant"(uuid) from public, anon, authenticated;
grant execute on function "api"."revoke_oauth_grant"(uuid) to service_role;

create or replace function "api"."my_oauth_grants"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_oauth_grants"() $$;
revoke execute on function "api"."my_oauth_grants"() from public, anon;
grant execute on function "api"."my_oauth_grants"() to authenticated, service_role;

create or replace function "api"."revoke_my_oauth_grant"(grant_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_my_oauth_grant"($1) $$;
revoke execute on function "api"."revoke_my_oauth_grant"(uuid) from public, anon;
grant execute on function "api"."revoke_my_oauth_grant"(uuid) to authenticated, service_role;

create or replace function "api"."revoke_oauth_token"(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_oauth_token"($1, $2, $3) $$;
revoke execute on function "api"."revoke_oauth_token"(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "api"."revoke_oauth_token"(text, timestamptz, uuid) to service_role;

create or replace function "api"."is_oauth_token_revoked"(jti text, grant_id text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."is_oauth_token_revoked"($1, $2) $$;
revoke execute on function "api"."is_oauth_token_revoked"(text, text) from public, anon, authenticated;
grant execute on function "api"."is_oauth_token_revoked"(text, text) to service_role;

create or replace function "api"."purge_oauth_server"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_oauth_server"() $$;
revoke execute on function "api"."purge_oauth_server"() from public, anon, authenticated;
grant execute on function "api"."purge_oauth_server"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block-data oauth-server
-- @bsb-hash sha256:fab570c8a0c09333723619c92dc55f7398532ffcd876d492a19b0cb2362b9a2f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('oauth-server', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block oauth-server@1 managed
-- @bsb-hash sha256:f3b2db264efc1d2b18be89abfba6ddbfd268c560bbe2587f1298a719353a24c3
-- Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOAuthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- OAuth 2.1 authorization server storage: registered clients (RFC 7591)
-- with hashed secrets, a user's grant per client, single-use authorization
-- codes bound to a PKCE S256 challenge (RFC 7636), device codes (RFC 8628)
-- and a revocation list of access token jtis. Tokens are issued elsewhere.
-- better_supabase.oauth_clients is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."oauth_clients" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."oauth_clients" add column if not exists "client_id" text check ("client_id" ~ '^[A-Za-z0-9._~-]{8,128}$');
alter table "better_supabase"."oauth_clients" add column if not exists "secret_hash" text check ("secret_hash" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."oauth_clients" add column if not exists "registration_token_hash" text check ("registration_token_hash" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."oauth_clients" add column if not exists "client_name" text check (length("client_name") <= 200);
alter table "better_supabase"."oauth_clients" add column if not exists "redirect_uris" text[] not null default '{}';
alter table "better_supabase"."oauth_clients" add column if not exists "grant_types" text[] not null default '{authorization_code}' check ("grant_types" <@ array['authorization_code', 'refresh_token', 'client_credentials', 'urn:ietf:params:oauth:grant-type:device_code']::text[]);
alter table "better_supabase"."oauth_clients" add column if not exists "token_endpoint_auth_method" text not null default 'client_secret_basic' check ("token_endpoint_auth_method" in ('none', 'client_secret_basic', 'client_secret_post'));
alter table "better_supabase"."oauth_clients" add column if not exists "scope" text;
alter table "better_supabase"."oauth_clients" add column if not exists "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object');
alter table "better_supabase"."oauth_clients" add column if not exists "created_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."oauth_clients" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."oauth_clients" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists oauth_clients_created_by_idx on "better_supabase"."oauth_clients" ("created_by");
create unique index if not exists "bsb_oauth_clients_client_id_key" on "better_supabase"."oauth_clients" ("client_id");
alter table "better_supabase"."oauth_clients" enable row level security;
grant all on "better_supabase"."oauth_clients" to service_role;

-- better_supabase.oauth_grants is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."oauth_grants" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."oauth_grants" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."oauth_grants" add column if not exists "client_id" text references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade;
alter table "better_supabase"."oauth_grants" add column if not exists "scopes" text[] not null default '{}';
alter table "better_supabase"."oauth_grants" add column if not exists "resource" text[] not null default '{}';
alter table "better_supabase"."oauth_grants" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."oauth_grants" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."oauth_grants" add column if not exists "revoked_at" timestamptz;
create unique index if not exists oauth_grants_active_idx on "better_supabase"."oauth_grants" ("user_id", "client_id") where "revoked_at" is null;
create index if not exists oauth_grants_client_idx on "better_supabase"."oauth_grants" ("client_id");
create index if not exists oauth_grants_user_idx on "better_supabase"."oauth_grants" ("user_id");
alter table "better_supabase"."oauth_grants" enable row level security;
grant all on "better_supabase"."oauth_grants" to service_role;

-- better_supabase.oauth_authorization_codes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "code_hash" text check ("code_hash" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "client_id" text references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "grant_id" uuid references "better_supabase"."oauth_grants" ("id") on delete cascade;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "redirect_uri" text;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "scope" text not null default '';
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "resource" text[] not null default '{}';
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "code_challenge" text check ("code_challenge" ~ '^[A-Za-z0-9_-]{43}$');
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "nonce" text;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "consumed_at" timestamptz;
alter table "better_supabase"."oauth_authorization_codes" add column if not exists "created_at" timestamptz not null default now();
create index if not exists oauth_authorization_codes_expires_idx on "better_supabase"."oauth_authorization_codes" ("expires_at");
create index if not exists oauth_authorization_codes_grant_idx on "better_supabase"."oauth_authorization_codes" ("grant_id");
create index if not exists oauth_authorization_codes_client_idx on "better_supabase"."oauth_authorization_codes" ("client_id");
create index if not exists oauth_authorization_codes_user_idx on "better_supabase"."oauth_authorization_codes" ("user_id");
alter table "better_supabase"."oauth_authorization_codes" enable row level security;
grant all on "better_supabase"."oauth_authorization_codes" to service_role;

-- better_supabase.oauth_device_codes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."oauth_device_codes" add column if not exists "device_code_hash" text check ("device_code_hash" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."oauth_device_codes" add column if not exists "user_code" text check ("user_code" ~ '^[A-Z0-9]{6,12}$');
alter table "better_supabase"."oauth_device_codes" add column if not exists "client_id" text references "better_supabase"."oauth_clients" ("client_id") on delete cascade on update cascade;
alter table "better_supabase"."oauth_device_codes" add column if not exists "scope" text not null default '';
alter table "better_supabase"."oauth_device_codes" add column if not exists "resource" text[] not null default '{}';
alter table "better_supabase"."oauth_device_codes" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'denied'));
alter table "better_supabase"."oauth_device_codes" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."oauth_device_codes" add column if not exists "grant_id" uuid references "better_supabase"."oauth_grants" ("id") on delete cascade;
alter table "better_supabase"."oauth_device_codes" add column if not exists "poll_interval" integer not null default 5 check ("poll_interval" between 1 and 300);
alter table "better_supabase"."oauth_device_codes" add column if not exists "last_polled_at" timestamptz;
alter table "better_supabase"."oauth_device_codes" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."oauth_device_codes" add column if not exists "consumed_at" timestamptz;
alter table "better_supabase"."oauth_device_codes" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists oauth_device_codes_user_code_idx on "better_supabase"."oauth_device_codes" ("user_code") where "status" = 'pending';
create index if not exists oauth_device_codes_expires_idx on "better_supabase"."oauth_device_codes" ("expires_at");
create index if not exists oauth_device_codes_grant_idx on "better_supabase"."oauth_device_codes" ("grant_id");
create index if not exists oauth_device_codes_client_idx on "better_supabase"."oauth_device_codes" ("client_id");
create index if not exists oauth_device_codes_user_idx on "better_supabase"."oauth_device_codes" ("user_id");
alter table "better_supabase"."oauth_device_codes" enable row level security;
grant all on "better_supabase"."oauth_device_codes" to service_role;

-- better_supabase.oauth_revocations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."oauth_revocations" add column if not exists "jti" text check (length("jti") between 1 and 256);
alter table "better_supabase"."oauth_revocations" add column if not exists "grant_id" uuid;
alter table "better_supabase"."oauth_revocations" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."oauth_revocations" add column if not exists "created_at" timestamptz not null default now();
create index if not exists oauth_revocations_expires_idx on "better_supabase"."oauth_revocations" ("expires_at");
create unique index if not exists "bsb_oauth_revocations_jti_key" on "better_supabase"."oauth_revocations" ("jti");
alter table "better_supabase"."oauth_revocations" enable row level security;
grant all on "better_supabase"."oauth_revocations" to service_role;

-- The user's active grant for the client, widened to the scopes; a new one
-- when there is none. Only the definer functions below call it.
drop function if exists "better_supabase"."oauth_grant_for"(uuid, text, text[]);
create or replace function "better_supabase"."oauth_grant_for"(user_id uuid, client_id text, scopes text[], resource text[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g
  set "scopes" = array(select distinct s from unnest(g."scopes" || oauth_grant_for.scopes) s order by s),
    "resource" = array(select distinct r from unnest(g."resource" || coalesce(oauth_grant_for.resource, '{}')) r order by r),
    "updated_at" = now()
  where g."user_id" = oauth_grant_for.user_id
    and g."client_id" = oauth_grant_for.client_id
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    insert into "better_supabase"."oauth_grants" ("user_id", "client_id", "scopes", "resource")
    values (oauth_grant_for.user_id, oauth_grant_for.client_id,
      array(select distinct s from unnest(oauth_grant_for.scopes) s order by s),
      array(select distinct r from unnest(coalesce(oauth_grant_for.resource, '{}')) r order by r))
    returning * into v_row;
    null;
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."oauth_grant_for"(uuid, text, text[], text[]) from public, anon, authenticated, service_role;

-- Registers a client (RFC 7591). The secret and registration token arrive hashed.
create or replace function "better_supabase"."register_oauth_client"(
  client_id text, secret_hash text, registration_token_hash text, client_name text,
  redirect_uris text[], grant_types text[], token_endpoint_auth_method text, scope text,
  metadata jsonb, created_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_clients" ("client_id", "secret_hash", "registration_token_hash", "client_name",
    "redirect_uris", "grant_types", "token_endpoint_auth_method", "scope", "metadata", "created_by")
  values (register_oauth_client.client_id, register_oauth_client.secret_hash,
    register_oauth_client.registration_token_hash, register_oauth_client.client_name,
    coalesce(register_oauth_client.redirect_uris, '{}'),
    coalesce(register_oauth_client.grant_types, '{authorization_code}'),
    better_supabase.as_column_type(coalesce(register_oauth_client.token_endpoint_auth_method, 'client_secret_basic'), (null::"better_supabase"."oauth_clients")."token_endpoint_auth_method"),
    register_oauth_client.scope, coalesce(register_oauth_client.metadata, '{}'::jsonb),
    register_oauth_client.created_by)
  returning * into v_row;
  null;
  return jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."register_oauth_client"(text, text, text, text, text[], text[], text, text, jsonb, uuid) to service_role;

-- A client without its hashes, or null.
create or replace function "better_supabase"."oauth_client"(client_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at") from "better_supabase"."oauth_clients" c where c."client_id" = oauth_client.client_id);
end;
$$;
revoke execute on function "better_supabase"."oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_client"(text) to service_role;

-- The client when the secret hash matches (null secret for a public client), or null.
create or replace function "better_supabase"."verify_oauth_client"(client_id text, secret_hash text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object(
      'clientId', c."client_id",
      'name', c."client_name",
      'redirectUris', to_jsonb(c."redirect_uris"),
      'grantTypes', to_jsonb(c."grant_types"),
      'tokenEndpointAuthMethod', c."token_endpoint_auth_method",
      'scope', c."scope",
      'metadata', c."metadata",
      'createdBy', c."created_by",
      'createdAt', c."created_at",
      'updatedAt', c."updated_at")
    from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_client.client_id
      and c."secret_hash" is not distinct from verify_oauth_client.secret_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_client"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_client"(text, text) to service_role;

-- Whether the registration access token (RFC 7592) belongs to the client.
create or replace function "better_supabase"."verify_oauth_registration_token"(client_id text, token_hash text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = verify_oauth_registration_token.client_id
      and c."registration_token_hash" = verify_oauth_registration_token.token_hash
  );
end;
$$;
revoke execute on function "better_supabase"."verify_oauth_registration_token"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."verify_oauth_registration_token"(text, text) to service_role;

-- Replaces a client's metadata (RFC 7592); null keeps a value. Null when unknown.
create or replace function "better_supabase"."update_oauth_client"(
  client_id text, client_name text, redirect_uris text[], grant_types text[], scope text, metadata jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_clients";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set
    "client_name" = coalesce(update_oauth_client.client_name, c."client_name"),
    "redirect_uris" = coalesce(update_oauth_client.redirect_uris, c."redirect_uris"),
    "grant_types" = coalesce(update_oauth_client.grant_types, c."grant_types"),
    "scope" = coalesce(update_oauth_client.scope, c."scope"),
    "metadata" = coalesce(update_oauth_client.metadata, c."metadata"),
    "updated_at" = now()
  where c."client_id" = update_oauth_client.client_id
  returning c.* into v_row;
  return case when v_row."id" is null then null else jsonb_build_object(
      'clientId', v_row."client_id",
      'name', v_row."client_name",
      'redirectUris', to_jsonb(v_row."redirect_uris"),
      'grantTypes', to_jsonb(v_row."grant_types"),
      'tokenEndpointAuthMethod', v_row."token_endpoint_auth_method",
      'scope', v_row."scope",
      'metadata', v_row."metadata",
      'createdBy', v_row."created_by",
      'createdAt', v_row."created_at",
      'updatedAt', v_row."updated_at") end;
end;
$$;
revoke execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."update_oauth_client"(text, text, text[], text[], text, jsonb) to service_role;

-- Sets a new secret hash for a confidential client; false when unknown or public.
create or replace function "better_supabase"."rotate_oauth_client_secret"(client_id text, secret_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_clients" c set "secret_hash" = rotate_oauth_client_secret.secret_hash, "updated_at" = now()
  where c."client_id" = rotate_oauth_client_secret.client_id and c."token_endpoint_auth_method" <> 'none';
  return found;
end;
$$;
revoke execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."rotate_oauth_client_secret"(text, text) to service_role;

-- Deletes a client with its grants and codes; its tokens fail the grant check.
create or replace function "better_supabase"."delete_oauth_client"(client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_clients" c where c."client_id" = delete_oauth_client.client_id;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_oauth_client"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."delete_oauth_client"(text) to service_role;

-- Stores an authorization code after consent, under the user's grant.
drop function if exists "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text);
create or replace function "better_supabase"."create_oauth_authorization_code"(
  code_hash text, client_id text, user_id uuid, redirect_uri text, scope text,
  code_challenge text, ttl interval, nonce text default null, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_authorization_code.client_id
      and 'authorization_code' = any (c."grant_types")
      and (create_oauth_authorization_code.redirect_uri is null
        or create_oauth_authorization_code.redirect_uri = any (c."redirect_uris"))
  ) then
    raise exception 'the client is unknown, can''t use codes, or didn''t register the redirect URI' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  v_grant := "better_supabase"."oauth_grant_for"(create_oauth_authorization_code.user_id,
    create_oauth_authorization_code.client_id, array(select s from unnest(regexp_split_to_array(btrim(coalesce(create_oauth_authorization_code.scope, '')), '\s+')) s where s <> ''),
    coalesce(create_oauth_authorization_code.resource, '{}'));
  insert into "better_supabase"."oauth_authorization_codes" ("code_hash", "client_id", "user_id", "grant_id", "redirect_uri",
    "scope", "resource", "code_challenge", "nonce", "expires_at")
  values (create_oauth_authorization_code.code_hash, create_oauth_authorization_code.client_id,
    create_oauth_authorization_code.user_id, v_grant, create_oauth_authorization_code.redirect_uri,
    coalesce(create_oauth_authorization_code.scope, ''), coalesce(create_oauth_authorization_code.resource, '{}'),
    create_oauth_authorization_code.code_challenge,
    create_oauth_authorization_code.nonce, now() + create_oauth_authorization_code.ttl);
  return jsonb_build_object('grantId', v_grant);
end;
$$;
revoke execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_authorization_code"(text, text, uuid, text, text, text, interval, text, text[]) to service_role;

-- Consumes a code once. code_challenge is S256 of the presented verifier.
-- A code presented twice revokes its grant (RFC 9700 section 4.5).
drop function if exists "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text);
create or replace function "better_supabase"."redeem_oauth_authorization_code"(
  code_hash text, client_id text, redirect_uri text, code_challenge text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code "better_supabase"."oauth_authorization_codes";
  v_grant "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_code from "better_supabase"."oauth_authorization_codes" a
  where a."code_hash" = redeem_oauth_authorization_code.code_hash
  for update;
  if v_code."code_hash" is null then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_code."consumed_at" is not null then
    update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
    where g."id" = v_code."grant_id" and g."revoked_at" is null
    returning g.* into v_grant;
    if v_grant."id" is not null then
      null;
    end if;
    return jsonb_build_object('status', 'invalid', 'replayed', true);
  end if;
  update "better_supabase"."oauth_authorization_codes" a set "consumed_at" = now()
  where a."code_hash" = v_code."code_hash";
  if v_code."expires_at" <= now()
    or v_code."client_id" <> redeem_oauth_authorization_code.client_id
    or v_code."redirect_uri" is distinct from redeem_oauth_authorization_code.redirect_uri
    or v_code."code_challenge" <> redeem_oauth_authorization_code.code_challenge
    or not exists (
      select 1 from "better_supabase"."oauth_grants" g
      where g."id" = v_code."grant_id" and g."revoked_at" is null
    ) then
    return jsonb_build_object('status', 'invalid');
  end if;
  -- RFC 8707 section 2.2: a token request may narrow the resources of the
  -- code but never widen them.
  if redeem_oauth_authorization_code.resource is not null
    and not redeem_oauth_authorization_code.resource <@ v_code."resource" then
    return jsonb_build_object('status', 'invalid', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_code."user_id", 'clientId', v_code."client_id",
    'grantId', v_code."grant_id", 'scope', v_code."scope", 'nonce', v_code."nonce",
    'resource', to_jsonb(coalesce(redeem_oauth_authorization_code.resource, v_code."resource")));
end;
$$;
revoke execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_oauth_authorization_code"(text, text, text, text, text[]) to service_role;

-- Starts a device authorization (RFC 8628 section 3.2).
drop function if exists "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer);
create or replace function "better_supabase"."create_oauth_device_code"(
  device_code_hash text, user_code text, client_id text, scope text, ttl interval, poll_interval integer default 5,
  resource text[] default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."oauth_clients" c
    where c."client_id" = create_oauth_device_code.client_id
      and 'urn:ietf:params:oauth:grant-type:device_code' = any (c."grant_types")
  ) then
    raise exception 'the client is unknown or can''t use the device flow' using errcode = '22023', hint = 'OAUTH_CLIENT_INVALID';
  end if;
  insert into "better_supabase"."oauth_device_codes" ("device_code_hash", "user_code", "client_id", "scope",
    "resource", "poll_interval", "expires_at")
  values (create_oauth_device_code.device_code_hash, create_oauth_device_code.user_code,
    create_oauth_device_code.client_id, coalesce(create_oauth_device_code.scope, ''),
    coalesce(create_oauth_device_code.resource, '{}'),
    coalesce(create_oauth_device_code.poll_interval, 5), now() + create_oauth_device_code.ttl);
  return true;
end;
$$;
revoke execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."create_oauth_device_code"(text, text, text, text, interval, integer, text[]) to service_role;

-- The pending request behind a user code, for the verification page, or null.
create or replace function "better_supabase"."oauth_device_request"(user_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('clientId', d."client_id", 'scope', d."scope", 'resource', to_jsonb(d."resource"), 'expiresAt', d."expires_at")
    from "better_supabase"."oauth_device_codes" d
    where d."user_code" = oauth_device_request.user_code
      and d."status" = 'pending'
      and d."expires_at" > now()
  );
end;
$$;
revoke execute on function "better_supabase"."oauth_device_request"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."oauth_device_request"(text) to service_role;

-- Approves or denies a pending user code for the signed-in user; false when
-- there is no such pending, unexpired code.
create or replace function "better_supabase"."decide_oauth_device_code"(user_code text, user_id uuid, approve boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
  v_grant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."user_code" = decide_oauth_device_code.user_code
    and d."status" = 'pending'
    and d."expires_at" > now()
  for update;
  if v_device."device_code_hash" is null then
    return false;
  end if;
  if decide_oauth_device_code.approve then
    v_grant := "better_supabase"."oauth_grant_for"(decide_oauth_device_code.user_id, v_device."client_id",
      array(select s from unnest(regexp_split_to_array(btrim(coalesce(v_device."scope", '')), '\s+')) s where s <> ''), v_device."resource");
  end if;
  update "better_supabase"."oauth_device_codes" d set
    "status" = better_supabase.as_column_type(case when decide_oauth_device_code.approve then 'approved' else 'denied' end, (null::"better_supabase"."oauth_device_codes")."status"),
    "user_id" = decide_oauth_device_code.user_id,
    "grant_id" = v_grant
  where d."device_code_hash" = v_device."device_code_hash";
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."decide_oauth_device_code"(text, uuid, boolean) to service_role;

-- A token request's poll (RFC 8628 section 3.5): pending, slow_down,
-- access_denied, expired_token, invalid_grant, or ok once.
drop function if exists "better_supabase"."poll_oauth_device_code"(text, text);
create or replace function "better_supabase"."poll_oauth_device_code"(device_code_hash text, client_id text, resource text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device "better_supabase"."oauth_device_codes";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  select * into v_device from "better_supabase"."oauth_device_codes" d
  where d."device_code_hash" = poll_oauth_device_code.device_code_hash
  for update;
  if v_device."device_code_hash" is null
    or v_device."client_id" <> poll_oauth_device_code.client_id
    or v_device."consumed_at" is not null then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if v_device."expires_at" <= now() then
    return jsonb_build_object('status', 'expired_token');
  end if;
  if v_device."status" = 'denied' then
    update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'access_denied');
  end if;
  if v_device."status" = 'pending' then
    if v_device."last_polled_at" is not null
      and v_device."last_polled_at" + make_interval(secs => v_device."poll_interval") > now() then
      update "better_supabase"."oauth_device_codes" d set "poll_interval" = least(d."poll_interval" + 5, 300), "last_polled_at" = now()
      where d."device_code_hash" = v_device."device_code_hash";
      return jsonb_build_object('status', 'slow_down', 'interval', least(v_device."poll_interval" + 5, 300));
    end if;
    update "better_supabase"."oauth_device_codes" d set "last_polled_at" = now()
    where d."device_code_hash" = v_device."device_code_hash";
    return jsonb_build_object('status', 'authorization_pending', 'interval', v_device."poll_interval");
  end if;
  update "better_supabase"."oauth_device_codes" d set "consumed_at" = now()
  where d."device_code_hash" = v_device."device_code_hash";
  if not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id" = v_device."grant_id" and g."revoked_at" is null
  ) then
    return jsonb_build_object('status', 'invalid_grant');
  end if;
  if poll_oauth_device_code.resource is not null
    and not poll_oauth_device_code.resource <@ v_device."resource" then
    return jsonb_build_object('status', 'invalid_grant', 'invalidTarget', true);
  end if;
  return jsonb_build_object('status', 'ok', 'userId', v_device."user_id", 'clientId', v_device."client_id",
    'grantId', v_device."grant_id", 'scope', v_device."scope",
    'resource', to_jsonb(coalesce(poll_oauth_device_code.resource, v_device."resource")));
end;
$$;
revoke execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) from public, anon, authenticated;
grant execute on function "better_supabase"."poll_oauth_device_code"(text, text, text[]) to service_role;

-- A user's grants, newest first; revoked ones only with include_revoked.
create or replace function "better_supabase"."list_oauth_grants"(user_id uuid, include_revoked boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = list_oauth_grants.user_id
      and (list_oauth_grants.include_revoked or g."revoked_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_oauth_grants"(uuid, boolean) to service_role;

-- Revokes a grant, which ends every token and code issued under it.
create or replace function "better_supabase"."revoke_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_oauth_grant.grant_id and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_grant"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_grant"(uuid) to service_role;

-- The signed-in user's active grants, for a "connected apps" page.
create or replace function "better_supabase"."my_oauth_grants"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', g."id",
      'userId', g."user_id",
      'clientId', g."client_id",
      'scopes', to_jsonb(g."scopes"),
      'resource', to_jsonb(g."resource"),
      'createdAt', g."created_at",
      'updatedAt', g."updated_at",
      'revokedAt', g."revoked_at") || jsonb_build_object('clientName', c."client_name") order by g."created_at" desc)
    from "better_supabase"."oauth_grants" g
    join "better_supabase"."oauth_clients" c on c."client_id" = g."client_id"
    where g."user_id" = (select auth.uid())
      and g."revoked_at" is null
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."my_oauth_grants"() from public, anon;
grant execute on function "better_supabase"."my_oauth_grants"() to authenticated, service_role;

-- Revokes one of the signed-in user's grants; false when it isn't theirs or active.
create or replace function "better_supabase"."revoke_my_oauth_grant"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."oauth_grants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."oauth_grants" g set "revoked_at" = now(), "updated_at" = now()
  where g."id" = revoke_my_oauth_grant.grant_id
    and g."user_id" = (select auth.uid())
    and g."revoked_at" is null
  returning g.* into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_my_oauth_grant"(uuid) to authenticated, service_role;

-- Adds an access token's jti to the revocation list until it expires.
create or replace function "better_supabase"."revoke_oauth_token"(jti text, expires_at timestamptz, grant_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  insert into "better_supabase"."oauth_revocations" ("jti", "grant_id", "expires_at")
  values (revoke_oauth_token.jti, revoke_oauth_token.grant_id, revoke_oauth_token.expires_at)
  on conflict ("jti") do update
    set "expires_at" = greatest("better_supabase"."oauth_revocations"."expires_at", excluded."expires_at");
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."revoke_oauth_token"(text, timestamptz, uuid) to service_role;

-- True when the jti is on the revocation list, or the grant is revoked or
-- gone. A grant id that isn't a uuid counts as gone.
create or replace function "better_supabase"."is_oauth_token_revoked"(jti text, grant_id text default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."oauth_revocations" r where r."jti" = is_oauth_token_revoked.jti) then
    return true;
  end if;
  if is_oauth_token_revoked.grant_id is null then
    return false;
  end if;
  return not exists (
    select 1 from "better_supabase"."oauth_grants" g
    where g."id"::text = is_oauth_token_revoked.grant_id
      and g."revoked_at" is null
  );
end;
$$;
revoke execute on function "better_supabase"."is_oauth_token_revoked"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."is_oauth_token_revoked"(text, text) to service_role;

-- Deletes expired codes, device codes and revocation entries.
create or replace function "better_supabase"."purge_oauth_server"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role calls the oauth-server functions' using errcode = '42501', hint = 'OAUTH_SERVER_FORBIDDEN';
  end if;
  delete from "better_supabase"."oauth_authorization_codes" a where a."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_device_codes" d where d."expires_at" < now() - interval '1 day';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."oauth_revocations" r where r."expires_at" < now();
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
$$;
revoke execute on function "better_supabase"."purge_oauth_server"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_oauth_server"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_106_oauth_server.sql
-- better-supabase module: oauth-server
-- @bsb-block-data oauth-server
-- @bsb-hash sha256:fab570c8a0c09333723619c92dc55f7398532ffcd876d492a19b0cb2362b9a2f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('oauth-server', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
