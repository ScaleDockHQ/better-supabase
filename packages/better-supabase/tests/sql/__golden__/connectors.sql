-- ==== alone: schema supabase/schemas/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block connectors@1 managed
-- @bsb-hash sha256:d13ecb026cb0505c4bccf6c07ee61888dac0f11b11e55cc4faa26e23f1026e82
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
create table if not exists "better_supabase"."connector_servers" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "url" text not null check ("url" ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))' and length("url") <= 2000),
  "transport" text not null default 'http' check ("transport" in ('http', 'sse')),
  "auth_type" text not null default 'oauth' check ("auth_type" in ('none', 'oauth', 'header')),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "scopes" text[] not null default '{}',
  "client_metadata" jsonb not null default '{}' check (jsonb_typeof("client_metadata") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("auth_type" = 'header') = ("credential_ref" is not null))
);
create index if not exists connector_servers_tenant_idx on "better_supabase"."connector_servers" ("organization_id");
create index if not exists connector_servers_created_by_idx on "better_supabase"."connector_servers" ("created_by");
alter table "better_supabase"."connector_servers" enable row level security;
revoke all on "better_supabase"."connector_servers" from anon, authenticated;
grant select on "better_supabase"."connector_servers" to authenticated;
grant all on "better_supabase"."connector_servers" to service_role;
drop policy if exists connector_servers_read on "better_supabase"."connector_servers";
create policy connector_servers_read on "better_supabase"."connector_servers" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')));

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
create table if not exists "better_supabase"."connector_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "organization_id" uuid not null,
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "scopes" text[] not null default '{}',
  "expires_at" timestamptz,
  "granted_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists connector_grants_active_idx on "better_supabase"."connector_grants" ("user_id", "server_id") where "revoked_at" is null;
create index if not exists connector_grants_server_idx on "better_supabase"."connector_grants" ("server_id");
create index if not exists connector_grants_user_idx on "better_supabase"."connector_grants" ("user_id");
alter table "better_supabase"."connector_grants" enable row level security;
revoke all on "better_supabase"."connector_grants" from anon, authenticated;
grant select on "better_supabase"."connector_grants" to authenticated;
grant all on "better_supabase"."connector_grants" to service_role;
drop policy if exists connector_grants_read on "better_supabase"."connector_grants";
create policy connector_grants_read on "better_supabase"."connector_grants" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
create table if not exists "better_supabase"."connector_sessions" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_key" text not null default '',
  "session_id" text,
  "initialize_result" jsonb,
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  primary key ("server_id", "user_id", "chat_key")
);
create index if not exists connector_sessions_expires_idx on "better_supabase"."connector_sessions" ("expires_at");
create index if not exists connector_sessions_user_idx on "better_supabase"."connector_sessions" ("user_id");
alter table "better_supabase"."connector_sessions" enable row level security;
revoke all on "better_supabase"."connector_sessions" from anon, authenticated;
grant select on "better_supabase"."connector_sessions" to authenticated;
grant all on "better_supabase"."connector_sessions" to service_role;
drop policy if exists connector_sessions_read on "better_supabase"."connector_sessions";
create policy connector_sessions_read on "better_supabase"."connector_sessions" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
create table if not exists "better_supabase"."connector_tool_fingerprints" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "fingerprint" text not null check (length("fingerprint") between 1 and 200),
  "tools" jsonb not null default '{}' check (jsonb_typeof("tools") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected')),
  "approved_by" uuid references auth.users (id) on delete set null,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("server_id", "fingerprint")
);
create index if not exists connector_tool_fingerprints_approved_by_idx on "better_supabase"."connector_tool_fingerprints" ("approved_by");
alter table "better_supabase"."connector_tool_fingerprints" enable row level security;
revoke all on "better_supabase"."connector_tool_fingerprints" from anon, authenticated;
grant select on "better_supabase"."connector_tool_fingerprints" to authenticated;
grant all on "better_supabase"."connector_tool_fingerprints" to service_role;
drop policy if exists connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints";
create policy connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints" for select to authenticated
  using (exists (select 1 from "better_supabase"."connector_servers" x where x."id" = "server_id"));

-- Adds a server (id null) or changes one ('ai.admin').
create or replace function "better_supabase"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function "better_supabase"."delete_connector_server"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  null;
  return v_grants;
end;
$$;
revoke execute on function "better_supabase"."delete_connector_server"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_connector_server"(uuid) to authenticated, service_role;

-- The tenant's servers with the caller's active grant on each.
create or replace function "better_supabase"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "better_supabase"."connector_servers" x where x."organization_id" = list_connector_servers.tenant
$$;
revoke execute on function "better_supabase"."list_connector_servers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_connector_servers"(uuid) to authenticated, service_role;

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function "better_supabase"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$$;
revoke execute on function "better_supabase"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_connector"(uuid, uuid) to authenticated, service_role;

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function "better_supabase"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$$;
revoke execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function "better_supabase"."revoke_connector_grant"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  null;
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_connector_grant"(uuid) to authenticated, service_role;

-- Grants that expire before a time, for the renewal job (service role).
create or replace function "better_supabase"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "better_supabase"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
revoke execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) to service_role;

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function "better_supabase"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "better_supabase"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
revoke execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) to service_role;

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function "better_supabase"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "better_supabase"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$$;
revoke execute on function "better_supabase"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_connector_session"(uuid, text) to authenticated, service_role;

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function "better_supabase"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$$;
revoke execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending, except the first one of a server, which is approved.
create or replace function "better_supabase"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

-- Approves or rejects a fingerprint ('ai.admin').
create or replace function "better_supabase"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

-- Deletes expired sessions (service role).
create or replace function "better_supabase"."purge_connector_sessions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_connector_sessions"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
create policy bsb_tenant_scope on "better_supabase"."connector_servers" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
create policy bsb_tenant_scope on "better_supabase"."connector_grants" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block connectors@1 managed
-- @bsb-hash sha256:ea70131c8034b736bffa4f5361bf4861025945e55ad35603c32b8955581976d4
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
create table if not exists "better_supabase"."connector_servers" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "url" text not null check ("url" ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))' and length("url") <= 2000),
  "transport" text not null default 'http' check ("transport" in ('http', 'sse')),
  "auth_type" text not null default 'oauth' check ("auth_type" in ('none', 'oauth', 'header')),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "scopes" text[] not null default '{}',
  "client_metadata" jsonb not null default '{}' check (jsonb_typeof("client_metadata") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("auth_type" = 'header') = ("credential_ref" is not null))
);
create index if not exists connector_servers_tenant_idx on "better_supabase"."connector_servers" ("organization_id");
create index if not exists connector_servers_created_by_idx on "better_supabase"."connector_servers" ("created_by");
alter table "better_supabase"."connector_servers" enable row level security;
revoke all on "better_supabase"."connector_servers" from anon, authenticated;
grant select on "better_supabase"."connector_servers" to authenticated;
grant all on "better_supabase"."connector_servers" to service_role;
drop policy if exists connector_servers_read on "better_supabase"."connector_servers";
create policy connector_servers_read on "better_supabase"."connector_servers" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')));

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
create table if not exists "better_supabase"."connector_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "organization_id" uuid not null,
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "scopes" text[] not null default '{}',
  "expires_at" timestamptz,
  "granted_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists connector_grants_active_idx on "better_supabase"."connector_grants" ("user_id", "server_id") where "revoked_at" is null;
create index if not exists connector_grants_server_idx on "better_supabase"."connector_grants" ("server_id");
create index if not exists connector_grants_user_idx on "better_supabase"."connector_grants" ("user_id");
alter table "better_supabase"."connector_grants" enable row level security;
revoke all on "better_supabase"."connector_grants" from anon, authenticated;
grant select on "better_supabase"."connector_grants" to authenticated;
grant all on "better_supabase"."connector_grants" to service_role;
drop policy if exists connector_grants_read on "better_supabase"."connector_grants";
create policy connector_grants_read on "better_supabase"."connector_grants" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
create table if not exists "better_supabase"."connector_sessions" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_key" text not null default '',
  "session_id" text,
  "initialize_result" jsonb,
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  primary key ("server_id", "user_id", "chat_key")
);
create index if not exists connector_sessions_expires_idx on "better_supabase"."connector_sessions" ("expires_at");
create index if not exists connector_sessions_user_idx on "better_supabase"."connector_sessions" ("user_id");
alter table "better_supabase"."connector_sessions" enable row level security;
revoke all on "better_supabase"."connector_sessions" from anon, authenticated;
grant select on "better_supabase"."connector_sessions" to authenticated;
grant all on "better_supabase"."connector_sessions" to service_role;
drop policy if exists connector_sessions_read on "better_supabase"."connector_sessions";
create policy connector_sessions_read on "better_supabase"."connector_sessions" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
create table if not exists "better_supabase"."connector_tool_fingerprints" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "fingerprint" text not null check (length("fingerprint") between 1 and 200),
  "tools" jsonb not null default '{}' check (jsonb_typeof("tools") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected')),
  "approved_by" uuid references auth.users (id) on delete set null,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("server_id", "fingerprint")
);
create index if not exists connector_tool_fingerprints_approved_by_idx on "better_supabase"."connector_tool_fingerprints" ("approved_by");
alter table "better_supabase"."connector_tool_fingerprints" enable row level security;
revoke all on "better_supabase"."connector_tool_fingerprints" from anon, authenticated;
grant select on "better_supabase"."connector_tool_fingerprints" to authenticated;
grant all on "better_supabase"."connector_tool_fingerprints" to service_role;
drop policy if exists connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints";
create policy connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints" for select to authenticated
  using (exists (select 1 from "better_supabase"."connector_servers" x where x."id" = "server_id"));

-- Adds a server (id null) or changes one ('ai.admin').
create or replace function "better_supabase"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('connector.saved', jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/connectors/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector.saved',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function "better_supabase"."delete_connector_server"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('connector.deleted', jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/connectors/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector.deleted',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return v_grants;
end;
$$;
revoke execute on function "better_supabase"."delete_connector_server"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_connector_server"(uuid) to authenticated, service_role;

-- The tenant's servers with the caller's active grant on each.
create or replace function "better_supabase"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "better_supabase"."connector_servers" x where x."organization_id" = list_connector_servers.tenant
$$;
revoke execute on function "better_supabase"."list_connector_servers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_connector_servers"(uuid) to authenticated, service_role;

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function "better_supabase"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$$;
revoke execute on function "better_supabase"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_connector"(uuid, uuid) to authenticated, service_role;

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function "better_supabase"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  perform "better_supabase".emit_event('connector_grant.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id"), 'organizations/' || v_row."organization_id"::text || '/connectors/' || v_row."server_id"::text, (v_row."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector_grant.created',
    category => 'integration',
    target_type => 'connector_grant',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id")
  );
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$$;
revoke execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function "better_supabase"."revoke_connector_grant"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  perform "better_supabase".emit_event('connector_grant.revoked', jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id"), 'organizations/' || v_row."organization_id"::text || '/connectors/' || v_row."server_id"::text, (v_row."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector_grant.revoked',
    category => 'integration',
    target_type => 'connector_grant',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id")
  );
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_connector_grant"(uuid) to authenticated, service_role;

-- Grants that expire before a time, for the renewal job (service role).
create or replace function "better_supabase"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "better_supabase"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
revoke execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) to service_role;

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function "better_supabase"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "better_supabase"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
revoke execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) to service_role;

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function "better_supabase"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "better_supabase"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$$;
revoke execute on function "better_supabase"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_connector_session"(uuid, text) to authenticated, service_role;

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function "better_supabase"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$$;
revoke execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending, except the first one of a server, which is approved.
create or replace function "better_supabase"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

-- Approves or rejects a fingerprint ('ai.admin').
create or replace function "better_supabase"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('connector.fingerprint_decided', jsonb_build_object('organizationId', v_server."organization_id"::text, 'serverId', v_server."id", 'name', v_server."name", 'fingerprint', decide_connector_fingerprint.fingerprint, 'approved', decide_connector_fingerprint.approved), 'organizations/' || v_server."organization_id"::text || '/connectors/' || v_server."id"::text, (v_server."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector.fingerprint_decided',
    category => 'integration',
    target_type => 'connector',
    record_id => v_server."id"::text,
    target_label => v_server."name",
    tenant => (v_server."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_server."organization_id"::text, 'serverId', v_server."id", 'name', v_server."name", 'fingerprint', decide_connector_fingerprint.fingerprint, 'approved', decide_connector_fingerprint.approved)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

-- Deletes expired sessions (service role).
create or replace function "better_supabase"."purge_connector_sessions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_connector_sessions"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
create policy bsb_tenant_scope on "better_supabase"."connector_servers" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
create policy bsb_tenant_scope on "better_supabase"."connector_grants" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block connectors@1 managed
-- @bsb-hash sha256:e51e3f306ff97bac51013cb079d75a1c3246b7bb9b45db4a8be54fba7ceefd10
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."connector_servers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."connector_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
create table if not exists "app_private"."connector_servers" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "url" text not null check ("url" ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))' and length("url") <= 2000),
  "transport" text not null default 'http' check ("transport" in ('http', 'sse')),
  "auth_type" text not null default 'oauth' check ("auth_type" in ('none', 'oauth', 'header')),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "scopes" text[] not null default '{}',
  "client_metadata" jsonb not null default '{}' check (jsonb_typeof("client_metadata") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("auth_type" = 'header') = ("credential_ref" is not null))
);
create index if not exists connector_servers_tenant_idx on "app_private"."connector_servers" ("organization_id");
create index if not exists connector_servers_created_by_idx on "app_private"."connector_servers" ("created_by");
alter table "app_private"."connector_servers" enable row level security;
revoke all on "app_private"."connector_servers" from anon, authenticated;
grant select on "app_private"."connector_servers" to authenticated;
grant all on "app_private"."connector_servers" to service_role;
drop policy if exists connector_servers_read on "app_private"."connector_servers";
create policy connector_servers_read on "app_private"."connector_servers" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')));

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
create table if not exists "app_private"."connector_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "server_id" uuid not null references "app_private"."connector_servers" ("id") on delete cascade,
  "organization_id" uuid not null,
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "scopes" text[] not null default '{}',
  "expires_at" timestamptz,
  "granted_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists connector_grants_active_idx on "app_private"."connector_grants" ("user_id", "server_id") where "revoked_at" is null;
create index if not exists connector_grants_server_idx on "app_private"."connector_grants" ("server_id");
create index if not exists connector_grants_user_idx on "app_private"."connector_grants" ("user_id");
alter table "app_private"."connector_grants" enable row level security;
revoke all on "app_private"."connector_grants" from anon, authenticated;
grant select on "app_private"."connector_grants" to authenticated;
grant all on "app_private"."connector_grants" to service_role;
drop policy if exists connector_grants_read on "app_private"."connector_grants";
create policy connector_grants_read on "app_private"."connector_grants" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
create table if not exists "app_private"."connector_sessions" (
  "server_id" uuid not null references "app_private"."connector_servers" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_key" text not null default '',
  "session_id" text,
  "initialize_result" jsonb,
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  primary key ("server_id", "user_id", "chat_key")
);
create index if not exists connector_sessions_expires_idx on "app_private"."connector_sessions" ("expires_at");
create index if not exists connector_sessions_user_idx on "app_private"."connector_sessions" ("user_id");
alter table "app_private"."connector_sessions" enable row level security;
revoke all on "app_private"."connector_sessions" from anon, authenticated;
grant select on "app_private"."connector_sessions" to authenticated;
grant all on "app_private"."connector_sessions" to service_role;
drop policy if exists connector_sessions_read on "app_private"."connector_sessions";
create policy connector_sessions_read on "app_private"."connector_sessions" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
create table if not exists "app_private"."connector_tool_fingerprints" (
  "server_id" uuid not null references "app_private"."connector_servers" ("id") on delete cascade,
  "fingerprint" text not null check (length("fingerprint") between 1 and 200),
  "tools" jsonb not null default '{}' check (jsonb_typeof("tools") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected')),
  "approved_by" uuid references auth.users (id) on delete set null,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("server_id", "fingerprint")
);
create index if not exists connector_tool_fingerprints_approved_by_idx on "app_private"."connector_tool_fingerprints" ("approved_by");
alter table "app_private"."connector_tool_fingerprints" enable row level security;
revoke all on "app_private"."connector_tool_fingerprints" from anon, authenticated;
grant select on "app_private"."connector_tool_fingerprints" to authenticated;
grant all on "app_private"."connector_tool_fingerprints" to service_role;
drop policy if exists connector_tool_fingerprints_read on "app_private"."connector_tool_fingerprints";
create policy connector_tool_fingerprints_read on "app_private"."connector_tool_fingerprints" for select to authenticated
  using (exists (select 1 from "app_private"."connector_servers" x where x."id" = "server_id"));

-- Adds a server (id null) or changes one ('ai.admin').
create or replace function "app_private"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "app_private"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "app_private"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "app_private"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function "app_private"."delete_connector_server"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "app_private"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "app_private"."connector_servers" x where x."id" = v_row."id";
  null;
  return v_grants;
end;
$$;
revoke execute on function "app_private"."delete_connector_server"(uuid) from public, anon;
grant execute on function "app_private"."delete_connector_server"(uuid) to authenticated, service_role;

-- The tenant's servers with the caller's active grant on each.
create or replace function "app_private"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "app_private"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "app_private"."connector_servers" x where x."organization_id" = list_connector_servers.tenant
$$;
revoke execute on function "app_private"."list_connector_servers"(uuid) from public, anon;
grant execute on function "app_private"."list_connector_servers"(uuid) to authenticated, service_role;

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function "app_private"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "app_private"."connector_servers"%rowtype;
begin
  select * into v_row from "app_private"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "app_private"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$$;
revoke execute on function "app_private"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "app_private"."get_connector"(uuid, uuid) to authenticated, service_role;

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function "app_private"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "app_private"."connector_servers"%rowtype;
  v_old "app_private"."connector_grants"%rowtype;
  v_row "app_private"."connector_grants"%rowtype;
begin
  select * into v_server from "app_private"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "app_private"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "app_private"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$$;
revoke execute on function "app_private"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function "app_private"."revoke_connector_grant"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "app_private"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  null;
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$$;
revoke execute on function "app_private"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "app_private"."revoke_connector_grant"(uuid) to authenticated, service_role;

-- Grants that expire before a time, for the renewal job (service role).
create or replace function "app_private"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "app_private"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
revoke execute on function "app_private"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "app_private"."expiring_connector_grants"(timestamptz, integer) to service_role;

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function "app_private"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "app_private"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
revoke execute on function "app_private"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."renew_connector_grant"(uuid, timestamptz) to service_role;

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function "app_private"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "app_private"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$$;
revoke execute on function "app_private"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "app_private"."get_connector_session"(uuid, text) to authenticated, service_role;

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function "app_private"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "app_private"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "app_private"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "app_private"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "app_private"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$$;
revoke execute on function "app_private"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "app_private"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending, except the first one of a server, which is approved.
create or replace function "app_private"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "app_private"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "app_private"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "app_private"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "app_private"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "app_private"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
revoke execute on function "app_private"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "app_private"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

-- Approves or rejects a fingerprint ('ai.admin').
create or replace function "app_private"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "app_private"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "app_private"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "app_private"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "app_private"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

-- Deletes expired sessions (service role).
create or replace function "app_private"."purge_connector_sessions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "app_private"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "app_private"."purge_connector_sessions"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."connector_servers";
create policy bsb_tenant_scope on "app_private"."connector_servers" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."connector_grants";
create policy bsb_tenant_scope on "app_private"."connector_grants" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block connectors@1 managed
-- @bsb-hash sha256:5b7b3f1569747f40f1e90cda61c1792c413886eaded1e6b2f5e1ff956aa6569f
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
create table if not exists "better_supabase"."connector_servers" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "url" text not null check ("url" ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))' and length("url") <= 2000),
  "transport" text not null default 'http' check ("transport" in ('http', 'sse')),
  "auth_type" text not null default 'oauth' check ("auth_type" in ('none', 'oauth', 'header')),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "scopes" text[] not null default '{}',
  "client_metadata" jsonb not null default '{}' check (jsonb_typeof("client_metadata") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("auth_type" = 'header') = ("credential_ref" is not null))
);
create index if not exists connector_servers_tenant_idx on "better_supabase"."connector_servers" ("organization_id");
create index if not exists connector_servers_created_by_idx on "better_supabase"."connector_servers" ("created_by");
alter table "better_supabase"."connector_servers" enable row level security;
revoke all on "better_supabase"."connector_servers" from anon, authenticated;
grant select on "better_supabase"."connector_servers" to authenticated;
grant all on "better_supabase"."connector_servers" to service_role;
drop policy if exists connector_servers_read on "better_supabase"."connector_servers";
create policy connector_servers_read on "better_supabase"."connector_servers" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')));

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
create table if not exists "better_supabase"."connector_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "organization_id" uuid not null,
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "scopes" text[] not null default '{}',
  "expires_at" timestamptz,
  "granted_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists connector_grants_active_idx on "better_supabase"."connector_grants" ("user_id", "server_id") where "revoked_at" is null;
create index if not exists connector_grants_server_idx on "better_supabase"."connector_grants" ("server_id");
create index if not exists connector_grants_user_idx on "better_supabase"."connector_grants" ("user_id");
alter table "better_supabase"."connector_grants" enable row level security;
revoke all on "better_supabase"."connector_grants" from anon, authenticated;
grant select on "better_supabase"."connector_grants" to authenticated;
grant all on "better_supabase"."connector_grants" to service_role;
drop policy if exists connector_grants_read on "better_supabase"."connector_grants";
create policy connector_grants_read on "better_supabase"."connector_grants" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
create table if not exists "better_supabase"."connector_sessions" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_key" text not null default '',
  "session_id" text,
  "initialize_result" jsonb,
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  primary key ("server_id", "user_id", "chat_key")
);
create index if not exists connector_sessions_expires_idx on "better_supabase"."connector_sessions" ("expires_at");
create index if not exists connector_sessions_user_idx on "better_supabase"."connector_sessions" ("user_id");
alter table "better_supabase"."connector_sessions" enable row level security;
revoke all on "better_supabase"."connector_sessions" from anon, authenticated;
grant select on "better_supabase"."connector_sessions" to authenticated;
grant all on "better_supabase"."connector_sessions" to service_role;
drop policy if exists connector_sessions_read on "better_supabase"."connector_sessions";
create policy connector_sessions_read on "better_supabase"."connector_sessions" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
create table if not exists "better_supabase"."connector_tool_fingerprints" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "fingerprint" text not null check (length("fingerprint") between 1 and 200),
  "tools" jsonb not null default '{}' check (jsonb_typeof("tools") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected')),
  "approved_by" uuid references auth.users (id) on delete set null,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("server_id", "fingerprint")
);
create index if not exists connector_tool_fingerprints_approved_by_idx on "better_supabase"."connector_tool_fingerprints" ("approved_by");
alter table "better_supabase"."connector_tool_fingerprints" enable row level security;
revoke all on "better_supabase"."connector_tool_fingerprints" from anon, authenticated;
grant select on "better_supabase"."connector_tool_fingerprints" to authenticated;
grant all on "better_supabase"."connector_tool_fingerprints" to service_role;
drop policy if exists connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints";
create policy connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints" for select to authenticated
  using (exists (select 1 from "better_supabase"."connector_servers" x where x."id" = "server_id"));

-- Adds a server (id null) or changes one ('ai.admin').
create or replace function "better_supabase"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function "better_supabase"."delete_connector_server"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  null;
  return v_grants;
end;
$$;
revoke execute on function "better_supabase"."delete_connector_server"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_connector_server"(uuid) to authenticated, service_role;

-- The tenant's servers with the caller's active grant on each.
create or replace function "better_supabase"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "better_supabase"."connector_servers" x where x."organization_id" = list_connector_servers.tenant
$$;
revoke execute on function "better_supabase"."list_connector_servers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_connector_servers"(uuid) to authenticated, service_role;

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function "better_supabase"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$$;
revoke execute on function "better_supabase"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_connector"(uuid, uuid) to authenticated, service_role;

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function "better_supabase"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$$;
revoke execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function "better_supabase"."revoke_connector_grant"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  null;
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_connector_grant"(uuid) to authenticated, service_role;

-- Grants that expire before a time, for the renewal job (service role).
create or replace function "better_supabase"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "better_supabase"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
revoke execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) to service_role;

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function "better_supabase"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "better_supabase"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
revoke execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) to service_role;

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function "better_supabase"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "better_supabase"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$$;
revoke execute on function "better_supabase"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_connector_session"(uuid, text) to authenticated, service_role;

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function "better_supabase"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$$;
revoke execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending, except the first one of a server, which is approved.
create or replace function "better_supabase"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

-- Approves or rejects a fingerprint ('ai.admin').
create or replace function "better_supabase"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

-- Deletes expired sessions (service role).
create or replace function "better_supabase"."purge_connector_sessions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_connector_sessions"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
create policy bsb_tenant_scope on "better_supabase"."connector_servers" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
create policy bsb_tenant_scope on "better_supabase"."connector_grants" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.connectors.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_connector_server"($1, $2, $3) $$;
revoke execute on function "api"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_connector_server"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_connector_server"($1) $$;
revoke execute on function "api"."delete_connector_server"(uuid) from public, anon;
grant execute on function "api"."delete_connector_server"(uuid) to authenticated, service_role;

create or replace function "api"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_connector_servers"($1) $$;
revoke execute on function "api"."list_connector_servers"(uuid) from public, anon;
grant execute on function "api"."list_connector_servers"(uuid) to authenticated, service_role;

create or replace function "api"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_connector"($1, $2) $$;
revoke execute on function "api"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "api"."get_connector"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_connector_grant"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "api"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

create or replace function "api"."revoke_connector_grant"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_connector_grant"($1) $$;
revoke execute on function "api"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "api"."revoke_connector_grant"(uuid) to authenticated, service_role;

create or replace function "api"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expiring_connector_grants"($1, $2) $$;
revoke execute on function "api"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "api"."expiring_connector_grants"(timestamptz, integer) to service_role;

create or replace function "api"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."renew_connector_grant"($1, $2) $$;
revoke execute on function "api"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "api"."renew_connector_grant"(uuid, timestamptz) to service_role;

create or replace function "api"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_connector_session"($1, $2) $$;
revoke execute on function "api"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "api"."get_connector_session"(uuid, text) to authenticated, service_role;

create or replace function "api"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_connector_session"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_connector_fingerprint"($1, $2, $3) $$;
revoke execute on function "api"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_connector_fingerprint"($1, $2, $3) $$;
revoke execute on function "api"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "api"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."purge_connector_sessions"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_connector_sessions"() $$;
revoke execute on function "api"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "api"."purge_connector_sessions"() to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block connectors@1 managed
-- @bsb-hash sha256:b821fa6565c4d61ea3cf13c40b7fdef496ac3983beca17bf8ca41602e1b63c6b
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
-- better_supabase.connector_servers is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."connector_servers" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."connector_servers" add column if not exists "organization_id" uuid;
alter table "better_supabase"."connector_servers" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."connector_servers" add column if not exists "url" text check ("url" ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))' and length("url") <= 2000);
alter table "better_supabase"."connector_servers" add column if not exists "transport" text not null default 'http' check ("transport" in ('http', 'sse'));
alter table "better_supabase"."connector_servers" add column if not exists "auth_type" text not null default 'oauth' check ("auth_type" in ('none', 'oauth', 'header'));
alter table "better_supabase"."connector_servers" add column if not exists "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'));
alter table "better_supabase"."connector_servers" add column if not exists "scopes" text[] not null default '{}';
alter table "better_supabase"."connector_servers" add column if not exists "client_metadata" jsonb not null default '{}' check (jsonb_typeof("client_metadata") = 'object');
alter table "better_supabase"."connector_servers" add column if not exists "enabled" boolean not null default true;
alter table "better_supabase"."connector_servers" add column if not exists "created_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."connector_servers" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."connector_servers" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists connector_servers_tenant_idx on "better_supabase"."connector_servers" ("organization_id");
create index if not exists connector_servers_created_by_idx on "better_supabase"."connector_servers" ("created_by");
alter table "better_supabase"."connector_servers" enable row level security;
grant select on "better_supabase"."connector_servers" to authenticated;
grant all on "better_supabase"."connector_servers" to service_role;
drop policy if exists bsb_connector_servers_select on "better_supabase"."connector_servers";
create policy bsb_connector_servers_select on "better_supabase"."connector_servers" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')));

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
-- better_supabase.connector_grants is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."connector_grants" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."connector_grants" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."connector_grants" add column if not exists "server_id" uuid references "better_supabase"."connector_servers" ("id") on delete cascade;
alter table "better_supabase"."connector_grants" add column if not exists "organization_id" uuid;
alter table "better_supabase"."connector_grants" add column if not exists "credential_ref" jsonb check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider');
alter table "better_supabase"."connector_grants" add column if not exists "scopes" text[] not null default '{}';
alter table "better_supabase"."connector_grants" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."connector_grants" add column if not exists "granted_at" timestamptz not null default now();
alter table "better_supabase"."connector_grants" add column if not exists "revoked_at" timestamptz;
create unique index if not exists connector_grants_active_idx on "better_supabase"."connector_grants" ("user_id", "server_id") where "revoked_at" is null;
create index if not exists connector_grants_server_idx on "better_supabase"."connector_grants" ("server_id");
create index if not exists connector_grants_user_idx on "better_supabase"."connector_grants" ("user_id");
alter table "better_supabase"."connector_grants" enable row level security;
grant select on "better_supabase"."connector_grants" to authenticated;
grant all on "better_supabase"."connector_grants" to service_role;
drop policy if exists bsb_connector_grants_select on "better_supabase"."connector_grants";
create policy bsb_connector_grants_select on "better_supabase"."connector_grants" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
-- better_supabase.connector_sessions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."connector_sessions" add column if not exists "server_id" uuid references "better_supabase"."connector_servers" ("id") on delete cascade;
alter table "better_supabase"."connector_sessions" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."connector_sessions" add column if not exists "chat_key" text not null default '';
alter table "better_supabase"."connector_sessions" add column if not exists "session_id" text;
alter table "better_supabase"."connector_sessions" add column if not exists "initialize_result" jsonb;
alter table "better_supabase"."connector_sessions" add column if not exists "last_used_at" timestamptz not null default now();
alter table "better_supabase"."connector_sessions" add column if not exists "expires_at" timestamptz;
create unique index if not exists "bsb_connector_sessions_chat_key" on "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key");
create index if not exists connector_sessions_expires_idx on "better_supabase"."connector_sessions" ("expires_at");
create index if not exists connector_sessions_user_idx on "better_supabase"."connector_sessions" ("user_id");
alter table "better_supabase"."connector_sessions" enable row level security;
grant select on "better_supabase"."connector_sessions" to authenticated;
grant all on "better_supabase"."connector_sessions" to service_role;
drop policy if exists bsb_connector_sessions_select on "better_supabase"."connector_sessions";
create policy bsb_connector_sessions_select on "better_supabase"."connector_sessions" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
-- better_supabase.connector_tool_fingerprints is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "server_id" uuid references "better_supabase"."connector_servers" ("id") on delete cascade;
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "fingerprint" text check (length("fingerprint") between 1 and 200);
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "tools" jsonb not null default '{}' check (jsonb_typeof("tools") = 'object');
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected'));
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "approved_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "approved_at" timestamptz;
alter table "better_supabase"."connector_tool_fingerprints" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_connector_tool_fingerprints_fingerprint_key" on "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint");
create index if not exists connector_tool_fingerprints_approved_by_idx on "better_supabase"."connector_tool_fingerprints" ("approved_by");
alter table "better_supabase"."connector_tool_fingerprints" enable row level security;
grant select on "better_supabase"."connector_tool_fingerprints" to authenticated;
grant all on "better_supabase"."connector_tool_fingerprints" to service_role;
drop policy if exists bsb_connector_tool_fingerprints_select on "better_supabase"."connector_tool_fingerprints";
create policy bsb_connector_tool_fingerprints_select on "better_supabase"."connector_tool_fingerprints" for select to authenticated
  using (exists (select 1 from "better_supabase"."connector_servers" x where x."id" = "server_id"));

-- Adds a server (id null) or changes one ('ai.admin').
create or replace function "better_supabase"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      better_supabase.as_column_type(coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), (null::"better_supabase"."connector_servers")."auth_type"), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = better_supabase.as_column_type(coalesce(save_connector_server.fields ->> 'transport', x."transport"::text), (null::"better_supabase"."connector_servers")."transport"),
    "auth_type" = better_supabase.as_column_type(coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"::text), (null::"better_supabase"."connector_servers")."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function "better_supabase"."delete_connector_server"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  null;
  return v_grants;
end;
$$;
revoke execute on function "better_supabase"."delete_connector_server"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_connector_server"(uuid) to authenticated, service_role;

-- The tenant's servers with the caller's active grant on each.
create or replace function "better_supabase"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "better_supabase"."connector_servers" x where x."organization_id" = list_connector_servers.tenant
$$;
revoke execute on function "better_supabase"."list_connector_servers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_connector_servers"(uuid) to authenticated, service_role;

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function "better_supabase"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$$;
revoke execute on function "better_supabase"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_connector"(uuid, uuid) to authenticated, service_role;

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function "better_supabase"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$$;
revoke execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function "better_supabase"."revoke_connector_grant"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  null;
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_connector_grant"(uuid) to authenticated, service_role;

-- Grants that expire before a time, for the renewal job (service role).
create or replace function "better_supabase"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "better_supabase"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
revoke execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) to service_role;

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function "better_supabase"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "better_supabase"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
revoke execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) to service_role;

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function "better_supabase"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "better_supabase"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$$;
revoke execute on function "better_supabase"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_connector_session"(uuid, text) to authenticated, service_role;

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function "better_supabase"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$$;
revoke execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending, except the first one of a server, which is approved.
create or replace function "better_supabase"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status"::text into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), better_supabase.as_column_type(v_status, (null::"better_supabase"."connector_tool_fingerprints")."status"),
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

-- Approves or rejects a fingerprint ('ai.admin').
create or replace function "better_supabase"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = better_supabase.as_column_type(case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end, (null::"better_supabase"."connector_tool_fingerprints")."status"),
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

-- Deletes expired sessions (service role).
create or replace function "better_supabase"."purge_connector_sessions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_connector_sessions"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
create policy bsb_tenant_scope on "better_supabase"."connector_servers" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('ai.read')))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
create policy bsb_tenant_scope on "better_supabase"."connector_grants" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block connectors@1 managed
-- @bsb-hash sha256:c7a9ddcc0a1b772445c65bbcd5799ea98ea8af3a3bd2172321365384b2cfb7dd
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- MCP servers a tenant connects its assistants to. A server names how to
-- authenticate (none, OAuth per user, or a header from credential_ref) and
-- never holds a token itself.
create table if not exists "better_supabase"."connector_servers" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "url" text not null check ("url" ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))' and length("url") <= 2000),
  "transport" text not null default 'http' check ("transport" in ('http', 'sse')),
  "auth_type" text not null default 'oauth' check ("auth_type" in ('none', 'oauth', 'header')),
  "credential_ref" jsonb check ("credential_ref" is null or (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider')),
  "scopes" text[] not null default '{}',
  "client_metadata" jsonb not null default '{}' check (jsonb_typeof("client_metadata") = 'object'),
  "enabled" boolean not null default true,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("auth_type" = 'header') = ("credential_ref" is not null))
);
create index if not exists connector_servers_tenant_idx on "better_supabase"."connector_servers" ("org_id");
create index if not exists connector_servers_created_by_idx on "better_supabase"."connector_servers" ("created_by");
alter table "better_supabase"."connector_servers" enable row level security;
revoke all on "better_supabase"."connector_servers" from anon, authenticated;
grant select on "better_supabase"."connector_servers" to authenticated;
grant all on "better_supabase"."connector_servers" to service_role;
drop policy if exists connector_servers_read on "better_supabase"."connector_servers";
create policy connector_servers_read on "better_supabase"."connector_servers" for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('ai.read')));

-- A user's connection to a server. credential_ref names where the provider
-- keeps the token (Vault, Vercel Connect); the row holds none.
create table if not exists "better_supabase"."connector_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "org_id" uuid not null,
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object' and "credential_ref" ? 'provider'),
  "scopes" text[] not null default '{}',
  "expires_at" timestamptz,
  "granted_at" timestamptz not null default now(),
  "revoked_at" timestamptz
);
create unique index if not exists connector_grants_active_idx on "better_supabase"."connector_grants" ("user_id", "server_id") where "revoked_at" is null;
create index if not exists connector_grants_server_idx on "better_supabase"."connector_grants" ("server_id");
create index if not exists connector_grants_user_idx on "better_supabase"."connector_grants" ("user_id");
alter table "better_supabase"."connector_grants" enable row level security;
revoke all on "better_supabase"."connector_grants" from anon, authenticated;
grant select on "better_supabase"."connector_grants" to authenticated;
grant all on "better_supabase"."connector_grants" to service_role;
drop policy if exists connector_grants_read on "better_supabase"."connector_grants";
create policy connector_grants_read on "better_supabase"."connector_grants" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The MCP session a user holds with a server per chat, so a later request
-- reuses it instead of initializing again.
create table if not exists "better_supabase"."connector_sessions" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_key" text not null default '',
  "session_id" text,
  "initialize_result" jsonb,
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz not null,
  primary key ("server_id", "user_id", "chat_key")
);
create index if not exists connector_sessions_expires_idx on "better_supabase"."connector_sessions" ("expires_at");
create index if not exists connector_sessions_user_idx on "better_supabase"."connector_sessions" ("user_id");
alter table "better_supabase"."connector_sessions" enable row level security;
revoke all on "better_supabase"."connector_sessions" from anon, authenticated;
grant select on "better_supabase"."connector_sessions" to authenticated;
grant all on "better_supabase"."connector_sessions" to service_role;
drop policy if exists connector_sessions_read on "better_supabase"."connector_sessions";
create policy connector_sessions_read on "better_supabase"."connector_sessions" for select to authenticated
  using ("user_id" = (select auth.uid()));

-- Fingerprints of a server's tool list. A list that changed waits for an
-- admin before an assistant may call it.
create table if not exists "better_supabase"."connector_tool_fingerprints" (
  "server_id" uuid not null references "better_supabase"."connector_servers" ("id") on delete cascade,
  "fingerprint" text not null check (length("fingerprint") between 1 and 200),
  "tools" jsonb not null default '{}' check (jsonb_typeof("tools") = 'object'),
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected')),
  "approved_by" uuid references auth.users (id) on delete set null,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("server_id", "fingerprint")
);
create index if not exists connector_tool_fingerprints_approved_by_idx on "better_supabase"."connector_tool_fingerprints" ("approved_by");
alter table "better_supabase"."connector_tool_fingerprints" enable row level security;
revoke all on "better_supabase"."connector_tool_fingerprints" from anon, authenticated;
grant select on "better_supabase"."connector_tool_fingerprints" to authenticated;
grant all on "better_supabase"."connector_tool_fingerprints" to service_role;
drop policy if exists connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints";
create policy connector_tool_fingerprints_read on "better_supabase"."connector_tool_fingerprints" for select to authenticated
  using (exists (select 1 from "better_supabase"."connector_servers" x where x."id" = "server_id"));

-- Adds a server (id null) or changes one ('ai.admin').
create or replace function "better_supabase"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("org_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."org_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."org_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_server"(uuid, uuid, jsonb) to authenticated, service_role;

-- Deletes a server and returns the grants it had, so the caller revokes
-- each credential through its provider.
create or replace function "better_supabase"."delete_connector_server"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."org_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  null;
  return v_grants;
end;
$$;
revoke execute on function "better_supabase"."delete_connector_server"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_connector_server"(uuid) to authenticated, service_role;

-- The tenant's servers with the caller's active grant on each.
create or replace function "better_supabase"."list_connector_servers"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."org_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."org_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "better_supabase"."connector_servers" x where x."org_id" = list_connector_servers.tenant
$$;
revoke execute on function "better_supabase"."list_connector_servers"(uuid) from public, anon;
grant execute on function "better_supabase"."list_connector_servers"(uuid) to authenticated, service_role;

-- A server and the active grant of a user on it: the caller's, or for the
-- service role the one of owner.
create or replace function "better_supabase"."get_connector"(id uuid, owner uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := case when coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."org_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."org_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$$;
revoke execute on function "better_supabase"."get_connector"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_connector"(uuid, uuid) to authenticated, service_role;

-- Records a user's grant after the provider stored the credential, revoking
-- the previous one (service role). Returns the new grant and the old one.
create or replace function "better_supabase"."record_connector_grant"(server_id uuid, owner uuid, credential_ref jsonb, scopes text[] default '{}', expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."org_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "org_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."org_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  null;
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."org_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."org_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$$;
revoke execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamptz) to service_role;

-- Revokes a grant (its owner or the service role) and returns it, so the
-- caller revokes the credential through its provider.
create or replace function "better_supabase"."revoke_connector_grant"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  null;
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."org_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_connector_grant"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_connector_grant"(uuid) to authenticated, service_role;

-- Grants that expire before a time, for the renewal job (service role).
create or replace function "better_supabase"."expiring_connector_grants"(before timestamptz, max_rows integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."org_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "better_supabase"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$$;
revoke execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expiring_connector_grants"(timestamptz, integer) to service_role;

-- Moves a grant's expiry after the provider refreshed the token (service role).
create or replace function "better_supabase"."renew_connector_grant"(id uuid, expires_at timestamptz)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with updated as (
    update "better_supabase"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$$;
revoke execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."renew_connector_grant"(uuid, timestamptz) to service_role;

-- The caller's MCP session with a server for a chat key, when it is still fresh.
create or replace function "better_supabase"."get_connector_session"(server_id uuid, chat_key text default '')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "better_supabase"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$$;
revoke execute on function "better_supabase"."get_connector_session"(uuid, text) from public, anon;
grant execute on function "better_supabase"."get_connector_session"(uuid, text) to authenticated, service_role;

-- Saves the caller's MCP session; a null session_id forgets it.
create or replace function "better_supabase"."save_connector_session"(server_id uuid, chat_key text default '', session_id text default null, initialize_result jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."org_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$$;
revoke execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_connector_session"(uuid, text, text, jsonb) to authenticated, service_role;

-- Checks a server's tool list fingerprint: 'approved', 'pending' or
-- 'rejected'. A new fingerprint is recorded as pending, except the first one of a server, which is approved.
create or replace function "better_supabase"."check_connector_fingerprint"(server_id uuid, fingerprint text, tools jsonb default '{}')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."org_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$$;
revoke execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) to authenticated, service_role;

-- Approves or rejects a fingerprint ('ai.admin').
create or replace function "better_supabase"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif(nullif(current_setting('role', true), ''), 'none'), nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."org_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) to authenticated, service_role;

-- Deletes expired sessions (service role).
create or replace function "better_supabase"."purge_connector_sessions"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from "better_supabase"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_connector_sessions"() from public, anon, authenticated;
grant execute on function "better_supabase"."purge_connector_sessions"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_servers";
create policy bsb_tenant_scope on "better_supabase"."connector_servers" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('ai.read')))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."connector_grants";
create policy bsb_tenant_scope on "better_supabase"."connector_grants" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_052_connectors.sql
-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:29335edcb89ba93004fa70b32f46f952067127195fa6ca8c364721346dd947e6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
