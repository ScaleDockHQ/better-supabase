-- ==== schema supabase/schemas/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bs-module domains@1 managed
-- Hostnames an organization serves its app on: custom domains verified by a DNS TXT record, subdomains of the platform domain, one primary per organization, and resolve_hostname() for the proxy.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Hostnames an organization serves its app on: its own domains, verified by a
-- DNS TXT record _better-supabase.<hostname>, and subdomains of
-- blocks.domains.options.platformDomain (unset), verified when added. One organization holds
-- each verified hostname, and each organization has at most one primary.
create table if not exists "better_supabase"."workspace_hostnames" (
  "id" uuid primary key default gen_random_uuid(),
  "workspace_id" uuid not null,
  "hostname" text not null check (length("hostname") <= 253 and "hostname" ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'),
  "kind" text not null default 'custom' check ("kind" in ('custom', 'subdomain')),
  "verification_token" text not null default replace(gen_random_uuid()::text, '-', ''),
  "verified_at" timestamptz,
  "is_primary" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default now(),
  unique ("workspace_id", "hostname"),
  check (not "is_primary" or "verified_at" is not null)
);
create unique index if not exists workspace_hostnames_verified_idx on "better_supabase"."workspace_hostnames" ("hostname") where "verified_at" is not null;
create unique index if not exists workspace_hostnames_primary_idx on "better_supabase"."workspace_hostnames" ("workspace_id") where "is_primary";
create index if not exists workspace_hostnames_created_by_idx on "better_supabase"."workspace_hostnames" ("created_by") where "created_by" is not null;
alter table "better_supabase"."workspace_hostnames" enable row level security;
revoke all on "better_supabase"."workspace_hostnames" from anon, authenticated;
grant all on "better_supabase"."workspace_hostnames" to service_role;

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
  v_row "better_supabase"."workspace_hostnames";
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
  select * into v_row from "better_supabase"."workspace_hostnames" x where x."workspace_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."workspace_hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."workspace_hostnames" ("workspace_id", "hostname", "kind", "verified_at")
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
    from "better_supabase"."workspace_hostnames" x where x."workspace_id" = list_hostnames.tenant
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
  v_row "better_supabase"."workspace_hostnames";
begin
  select * into v_row from "better_supabase"."workspace_hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."workspace_id", 'domains.manage'), false)) then
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
  v_row "better_supabase"."workspace_hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."workspace_hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."workspace_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."workspace_hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."workspace_hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
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
  v_row "better_supabase"."workspace_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workspace_hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."workspace_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."workspace_hostnames" x set "is_primary" = false where x."workspace_id" = v_row."workspace_id" and x."is_primary";
  update "better_supabase"."workspace_hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
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
  v_row "better_supabase"."workspace_hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workspace_hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."workspace_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."workspace_hostnames" x where x."id" = v_row."id";
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
    'organizationId', x."workspace_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."workspace_hostnames" p
      where p."workspace_id" = x."workspace_id" and p."is_primary"
    )
  )
  from "better_supabase"."workspace_hostnames" x
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

-- ==== data supabase/better-supabase-data/900_better_supabase_107_domains.sql
-- better-supabase module: domains
-- @bs-module-data domains
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('domains', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
