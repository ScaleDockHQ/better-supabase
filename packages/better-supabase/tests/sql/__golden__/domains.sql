-- ==== alone: schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block domains@1 managed
-- @bsb-hash sha256:492bebc8bb3e3703a26d41a65f04718a3f86e8d05a962a00e2d185cfe127e1b8
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."organization_hostnames";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists "better_supabase"."organization_hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "hostname" text not null check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("organization_id", "hostname"),
  check (not "is_primary" or "verified_at" is not null)
);
create unique index if not exists organization_hostnames_verified_idx on "better_supabase"."organization_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists organization_hostnames_primary_idx on "better_supabase"."organization_hostnames" ("organization_id") where "is_primary";
create index if not exists organization_hostnames_created_by_idx on "better_supabase"."organization_hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."organization_hostnames" enable row level security;
revoke all on "better_supabase"."organization_hostnames" from anon, authenticated;
grant all on "better_supabase"."organization_hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "better_supabase"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."organization_hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."organization_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."organization_hostnames" ("organization_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  null;
  if v_row."verified_at" is not null then
    null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function "better_supabase"."list_hostnames"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."organization_hostnames" x where x."organization_id" = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "better_supabase"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "better_supabase"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."organization_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "better_supabase"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."organization_hostnames" x set "is_primary" = false where x."organization_id" = v_row."organization_id" and x."is_primary";
  update "better_supabase"."organization_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "better_supabase"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."organization_hostnames" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "better_supabase"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."organization_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."organization_hostnames" p
      where p."organization_id" = x."organization_id" and p."is_primary"
    )
  )
  from "better_supabase"."organization_hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "better_supabase"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_hostnames"(uuid) from public, anon;
revoke execute on function "better_supabase"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "better_supabase"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."remove_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."resolve_hostname"(text) from public;
grant execute on function "better_supabase"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_hostnames"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "better_supabase"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."resolve_hostname"(text) to anon, authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block-data domains
-- @bsb-hash sha256:123582e0c6de571eddf1c9271a1f5c71c048fffd78a337b774dca2f3bc4b1997
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block domains@1 managed
-- @bsb-hash sha256:5804789165309870bea1950e470d3a64b8c08e49fbcd1c9300e27c05cca50d4c
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."organization_hostnames";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists "better_supabase"."organization_hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "hostname" text not null check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("organization_id", "hostname"),
  check (not "is_primary" or "verified_at" is not null)
);
create unique index if not exists organization_hostnames_verified_idx on "better_supabase"."organization_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists organization_hostnames_primary_idx on "better_supabase"."organization_hostnames" ("organization_id") where "is_primary";
create index if not exists organization_hostnames_created_by_idx on "better_supabase"."organization_hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."organization_hostnames" enable row level security;
revoke all on "better_supabase"."organization_hostnames" from anon, authenticated;
grant all on "better_supabase"."organization_hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "better_supabase"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."organization_hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."organization_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."organization_hostnames" ("organization_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  perform "better_supabase".emit_event('hostname.added', jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.added',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  if v_row."verified_at" is not null then
    perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function "better_supabase"."list_hostnames"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."organization_hostnames" x where x."organization_id" = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "better_supabase"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "better_supabase"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."organization_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => verify_hostname.actor
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "better_supabase"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."organization_hostnames" x set "is_primary" = false where x."organization_id" = v_row."organization_id" and x."is_primary";
  update "better_supabase"."organization_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.primary_set', jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.primary_set',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "better_supabase"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."organization_hostnames" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('hostname.removed', jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.removed',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "better_supabase"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."organization_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."organization_hostnames" p
      where p."organization_id" = x."organization_id" and p."is_primary"
    )
  )
  from "better_supabase"."organization_hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "better_supabase"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_hostnames"(uuid) from public, anon;
revoke execute on function "better_supabase"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "better_supabase"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."remove_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."resolve_hostname"(text) from public;
grant execute on function "better_supabase"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_hostnames"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "better_supabase"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."resolve_hostname"(text) to anon, authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block-data domains
-- @bsb-hash sha256:123582e0c6de571eddf1c9271a1f5c71c048fffd78a337b774dca2f3bc4b1997
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block domains@1 managed
-- @bsb-hash sha256:f474b482763212a3ce18abdfd875923326d20a952ad2fe506c68f07b695e12a7
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
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
    drop policy if exists bsb_tenant_scope on "app_private"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_select on "app_private"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_update on "app_private"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."organization_hostnames";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists "app_private"."organization_hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "hostname" text not null check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("organization_id", "hostname"),
  check (not "is_primary" or "verified_at" is not null)
);
create unique index if not exists organization_hostnames_verified_idx on "app_private"."organization_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists organization_hostnames_primary_idx on "app_private"."organization_hostnames" ("organization_id") where "is_primary";
create index if not exists organization_hostnames_created_by_idx on "app_private"."organization_hostnames" ("created_by") where "created_by" is not null;
alter table "app_private"."organization_hostnames" enable row level security;
revoke all on "app_private"."organization_hostnames" from anon, authenticated;
grant all on "app_private"."organization_hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "app_private"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."organization_hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "app_private"."organization_hostnames" x where x."organization_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "app_private"."organization_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "app_private"."organization_hostnames" ("organization_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  null;
  if v_row."verified_at" is not null then
    null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function "app_private"."list_hostnames"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "app_private"."organization_hostnames" x where x."organization_id" = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "app_private"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."organization_hostnames";
begin
  select * into v_row from "app_private"."organization_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "app_private"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."organization_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."organization_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "app_private"."organization_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "app_private"."organization_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "app_private"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."organization_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "app_private"."organization_hostnames" x set "is_primary" = false where x."organization_id" = v_row."organization_id" and x."is_primary";
  update "app_private"."organization_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "app_private"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."organization_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "app_private"."organization_hostnames" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "app_private"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."organization_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "app_private"."organization_hostnames" p
      where p."organization_id" = x."organization_id" and p."is_primary"
    )
  )
  from "app_private"."organization_hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "app_private"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "app_private"."list_hostnames"(uuid) from public, anon;
revoke execute on function "app_private"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "app_private"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "app_private"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "app_private"."remove_hostname"(uuid) from public, anon;
revoke execute on function "app_private"."resolve_hostname"(text) from public;
grant execute on function "app_private"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "app_private"."list_hostnames"(uuid) to authenticated, service_role;
grant execute on function "app_private"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "app_private"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "app_private"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "app_private"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "app_private"."resolve_hostname"(text) to anon, authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block-data domains
-- @bsb-hash sha256:123582e0c6de571eddf1c9271a1f5c71c048fffd78a337b774dca2f3bc4b1997
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block domains@1 managed
-- @bsb-hash sha256:4b581193afb7e09a443dad954c9507c8f9049986903752d9b5d43b226f2022cc
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."organization_hostnames";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists "better_supabase"."organization_hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "hostname" text not null check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("organization_id", "hostname"),
  check (not "is_primary" or "verified_at" is not null)
);
create unique index if not exists organization_hostnames_verified_idx on "better_supabase"."organization_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists organization_hostnames_primary_idx on "better_supabase"."organization_hostnames" ("organization_id") where "is_primary";
create index if not exists organization_hostnames_created_by_idx on "better_supabase"."organization_hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."organization_hostnames" enable row level security;
revoke all on "better_supabase"."organization_hostnames" from anon, authenticated;
grant all on "better_supabase"."organization_hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "better_supabase"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."organization_hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."organization_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."organization_hostnames" ("organization_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  null;
  if v_row."verified_at" is not null then
    null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function "better_supabase"."list_hostnames"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."organization_hostnames" x where x."organization_id" = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "better_supabase"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "better_supabase"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."organization_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "better_supabase"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."organization_hostnames" x set "is_primary" = false where x."organization_id" = v_row."organization_id" and x."is_primary";
  update "better_supabase"."organization_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "better_supabase"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."organization_hostnames" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "better_supabase"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."organization_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."organization_hostnames" p
      where p."organization_id" = x."organization_id" and p."is_primary"
    )
  )
  from "better_supabase"."organization_hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "better_supabase"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_hostnames"(uuid) from public, anon;
revoke execute on function "better_supabase"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "better_supabase"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."remove_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."resolve_hostname"(text) from public;
grant execute on function "better_supabase"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_hostnames"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "better_supabase"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."resolve_hostname"(text) to anon, authenticated, service_role;

-- blocks.domains.api: entry points for the Data API.
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

create or replace function "api"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_hostname"($1, $2) $$;
revoke execute on function "api"."add_hostname"(uuid, text) from public, anon;
grant execute on function "api"."add_hostname"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_hostnames"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_hostnames"($1) $$;
revoke execute on function "api"."list_hostnames"(uuid) from public, anon;
grant execute on function "api"."list_hostnames"(uuid) to authenticated, service_role;

create or replace function "api"."hostname_by_id"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."hostname_by_id"($1) $$;
revoke execute on function "api"."hostname_by_id"(uuid) from public, anon;
grant execute on function "api"."hostname_by_id"(uuid) to authenticated, service_role;

create or replace function "api"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."verify_hostname"($1, $2) $$;
revoke execute on function "api"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."verify_hostname"(uuid, uuid) to service_role;

create or replace function "api"."set_primary_hostname"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_primary_hostname"($1) $$;
revoke execute on function "api"."set_primary_hostname"(uuid) from public, anon;
grant execute on function "api"."set_primary_hostname"(uuid) to authenticated, service_role;

create or replace function "api"."remove_hostname"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_hostname"($1) $$;
revoke execute on function "api"."remove_hostname"(uuid) from public, anon;
grant execute on function "api"."remove_hostname"(uuid) to authenticated, service_role;

create or replace function "api"."resolve_hostname"(hostname text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_hostname"($1) $$;
revoke execute on function "api"."resolve_hostname"(text) from public;
grant execute on function "api"."resolve_hostname"(text) to anon, authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block-data domains
-- @bsb-hash sha256:123582e0c6de571eddf1c9271a1f5c71c048fffd78a337b774dca2f3bc4b1997
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block domains@1 managed
-- @bsb-hash sha256:8d0801ed1989b8afe62efcfd5705020812b987445cc52c15e2a0a3c4d29972a4
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."organization_hostnames";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
-- better_supabase.organization_hostnames is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."organization_hostnames" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."organization_hostnames" add column if not exists "organization_id" uuid;
alter table "better_supabase"."organization_hostnames" add column if not exists "hostname" text check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$');
alter table "better_supabase"."organization_hostnames" add column if not exists "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain'));
alter table "better_supabase"."organization_hostnames" add column if not exists "verification_token" text not null default replace(gen_random_uuid()::text, '-', '');
alter table "better_supabase"."organization_hostnames" add column if not exists "verified_at" timestamptz;
alter table "better_supabase"."organization_hostnames" add column if not exists "is_primary" boolean not null default false;
alter table "better_supabase"."organization_hostnames" add column if not exists "created_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."organization_hostnames" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists organization_hostnames_verified_idx on "better_supabase"."organization_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists organization_hostnames_primary_idx on "better_supabase"."organization_hostnames" ("organization_id") where "is_primary";
create index if not exists organization_hostnames_created_by_idx on "better_supabase"."organization_hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."organization_hostnames" enable row level security;
grant all on "better_supabase"."organization_hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "better_supabase"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."organization_hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."organization_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."organization_hostnames" ("organization_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, better_supabase.as_column_type(v_kind, (null::"better_supabase"."organization_hostnames")."kind"), case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  null;
  if v_row."verified_at" is not null then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function "better_supabase"."list_hostnames"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'hostname', x."hostname", 'kind', x."kind", 'verified_at', x."verified_at", 'is_primary', x."is_primary", 'created_by', x."created_by", 'created_at', x."created_at") || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."organization_hostnames" x where x."organization_id" = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "better_supabase"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "better_supabase"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."organization_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "better_supabase"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."organization_hostnames" x set "is_primary" = false where x."organization_id" = v_row."organization_id" and x."is_primary";
  update "better_supabase"."organization_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'hostname', v_row."hostname", 'kind', v_row."kind", 'verified_at', v_row."verified_at", 'is_primary', v_row."is_primary", 'created_by', v_row."created_by", 'created_at', v_row."created_at") || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "better_supabase"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."organization_hostnames" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "better_supabase"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."organization_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."organization_hostnames" p
      where p."organization_id" = x."organization_id" and p."is_primary"
    )
  )
  from "better_supabase"."organization_hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "better_supabase"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_hostnames"(uuid) from public, anon;
revoke execute on function "better_supabase"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "better_supabase"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."remove_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."resolve_hostname"(text) from public;
grant execute on function "better_supabase"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_hostnames"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "better_supabase"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."resolve_hostname"(text) to anon, authenticated, service_role;

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block-data domains
-- @bsb-hash sha256:123582e0c6de571eddf1c9271a1f5c71c048fffd78a337b774dca2f3bc4b1997
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block domains@1 managed
-- @bsb-hash sha256:862e1a28e891d98bfd62447445d66d4fe86855d81a2656f49f2cb9e07054f684
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."organization_hostnames";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."organization_hostnames";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists "better_supabase"."organization_hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "hostname" text not null check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("org_id", "hostname"),
  check (not "is_primary" or "verified_at" is not null)
);
create unique index if not exists organization_hostnames_verified_idx on "better_supabase"."organization_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists organization_hostnames_primary_idx on "better_supabase"."organization_hostnames" ("org_id") where "is_primary";
create index if not exists organization_hostnames_created_by_idx on "better_supabase"."organization_hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."organization_hostnames" enable row level security;
revoke all on "better_supabase"."organization_hostnames" from anon, authenticated;
grant all on "better_supabase"."organization_hostnames" to service_role;

-- Adds a hostname (needs the manage permission). A custom domain comes back
-- with the TXT record to publish; adding it again returns the same row.
create or replace function "better_supabase"."add_hostname"(tenant uuid, hostname text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."organization_hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."org_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."organization_hostnames" ("org_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  null;
  if v_row."verified_at" is not null then
    null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$$;

-- An organization's hostnames, primary first (read permission or the service role).
create or replace function "better_supabase"."list_hostnames"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."organization_hostnames" x where x."org_id" = list_hostnames.tenant
  );
end;
$$;

-- One hostname with its record, for the service role or a manager; null otherwise.
create or replace function "better_supabase"."hostname_by_id"(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Marks a hostname verified once the app has found its TXT record (service
-- role only). `actor`, when set, must hold the manage permission.
create or replace function "better_supabase"."verify_hostname"(id uuid, actor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."org_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."organization_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."organization_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Makes a verified hostname the organization's primary, the one other
-- hostnames redirect to.
create or replace function "better_supabase"."set_primary_hostname"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."organization_hostnames" x set "is_primary" = false where x."org_id" = v_row."org_id" and x."is_primary";
  update "better_supabase"."organization_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$$;

-- Removes a hostname; false when there is none the caller manages.
create or replace function "better_supabase"."remove_hostname"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."organization_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."organization_hostnames" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;

-- The organization a request's hostname belongs to, for the proxy: null
-- unless the hostname is verified. Open to anon, since the proxy runs before
-- sign-in; it returns nothing a DNS lookup doesn't already show.
create or replace function "better_supabase"."resolve_hostname"(hostname text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x."org_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."organization_hostnames" p
      where p."org_id" = x."org_id" and p."is_primary"
    )
  )
  from "better_supabase"."organization_hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$$;

revoke execute on function "better_supabase"."add_hostname"(uuid, text) from public, anon;
revoke execute on function "better_supabase"."list_hostnames"(uuid) from public, anon;
revoke execute on function "better_supabase"."hostname_by_id"(uuid) from public, anon;
revoke execute on function "better_supabase"."verify_hostname"(uuid, uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_primary_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."remove_hostname"(uuid) from public, anon;
revoke execute on function "better_supabase"."resolve_hostname"(text) from public;
grant execute on function "better_supabase"."add_hostname"(uuid, text) to authenticated, service_role;
grant execute on function "better_supabase"."list_hostnames"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."hostname_by_id"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."verify_hostname"(uuid, uuid) to service_role;
grant execute on function "better_supabase"."set_primary_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."remove_hostname"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."resolve_hostname"(text) to anon, authenticated, service_role;

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bsb-block-data domains
-- @bsb-hash sha256:123582e0c6de571eddf1c9271a1f5c71c048fffd78a337b774dca2f3bc4b1997
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
