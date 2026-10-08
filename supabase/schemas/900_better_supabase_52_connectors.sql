-- better-supabase module: connectors (0.5.1)
-- @bs-module connectors@1 managed
-- MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
  using ("organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read')));

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

-- Adds a server (id null) or changes one ('ai_chat.admin').
create or replace function "better_supabase"."save_connector_server"(tenant uuid, id uuid default null, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
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
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
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
  v_user uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.read'), false)) then
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
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai_chat.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
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
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
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
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai_chat.create'), false)) then
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
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai_chat.create'), false)) then
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

-- Approves or rejects a fingerprint ('ai_chat.admin').
create or replace function "better_supabase"."decide_connector_fingerprint"(server_id uuid, fingerprint text, approved boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  return found;
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

-- sql.modules.connectors.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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
