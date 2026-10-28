-- ==== schema supabase/schemas/900_better_supabase_090_service_accounts.sql
-- better-supabase module: service-accounts
-- @bsb-block service-accounts@1 managed
-- @bsb-hash sha256:f30ab95a3df751b66e5b3a0e961733cdcf643476d79b29991b208794c7760472
-- Non-human tenant members backed by auth.users rows that can't sign in, with roles through memberships. Organization-owned workflow versions and service webhook endpoints run as the tenant's default principal.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."service_principals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."service_principals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."service_principals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."service_principals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."service_principals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Non-human members of a tenant. Each row is an auth.users row that can't
-- sign in (no password, banned, app_metadata.bsb_service_principal),
-- created through the Auth admin API, and holds its role through a tenant
-- membership like any member. Organization-owned workflow versions and
-- service webhook endpoints run as the tenant's default principal.
create table if not exists "better_supabase"."service_principals" (
  "id" uuid primary key references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 120),
  "role" text not null check (length("role") between 1 and 200),
  "is_default" boolean not null default false,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "disabled_at" timestamptz,
  unique ("tenant_id", "name")
);
create index if not exists service_principals_tenant_idx on "better_supabase"."service_principals" ("tenant_id");
create index if not exists service_principals_created_by_idx on "better_supabase"."service_principals" ("created_by");
create unique index if not exists service_principals_default_idx on "better_supabase"."service_principals" ("tenant_id")
  where "is_default" and "disabled_at" is null;
alter table "better_supabase"."service_principals" add column if not exists "app_note" text;
alter table "better_supabase"."service_principals" enable row level security;
revoke all on "better_supabase"."service_principals" from public, anon, authenticated;
grant select on "better_supabase"."service_principals" to authenticated;
grant all on "better_supabase"."service_principals" to service_role;

drop policy if exists service_principals_read on "better_supabase"."service_principals";
create policy service_principals_read on "better_supabase"."service_principals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('service_accounts.read')));

-- Registers an auth.users row the service created for a principal and adds
-- its membership with role. The user must carry
-- app_metadata.bsb_service_principal and be banned, so a real account
-- never becomes one. With created_by, that member needs the manage
-- permission and may assign role. Service role only.
drop function if exists "better_supabase"."register_service_principal"(uuid, uuid, text, text, boolean, uuid);
create or replace function "better_supabase"."register_service_principal"(principal uuid, tenant uuid, name text, role text, is_default boolean default false, created_by uuid default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if register_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(register_service_principal.created_by, register_service_principal.tenant, 'service_accounts.manage'), false)
    and coalesce(better_supabase.can_assign_as(register_service_principal.created_by, register_service_principal.tenant, register_service_principal.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not exists (
    select 1 from auth.users u
    where u.id = register_service_principal.principal
      and coalesce((u.raw_app_meta_data ->> 'bsb_service_principal')::boolean, false)
      and u.banned_until > now() + interval '50 years'
  ) then
    raise exception 'The user is not a service principal: create it with createServiceAccounts().create' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_USER';
  end if;
  if not (register_service_principal.role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', register_service_principal.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if register_service_principal.is_default then
    update "better_supabase"."service_principals" set "is_default" = false
    where "tenant_id" = register_service_principal.tenant and "is_default";
  end if;
  insert into "better_supabase"."service_principals" ("id", "tenant_id", "name", "role", "is_default", "created_by")
  values (register_service_principal.principal, register_service_principal.tenant, register_service_principal.name,
    register_service_principal.role, coalesce(register_service_principal.is_default, false), register_service_principal.created_by);
  update "better_supabase"."service_principals" x set "app_note" = case when register_service_principal.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."service_principals", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(register_service_principal.fields) e where e.key in ('app_note'))) r
  where x."id" = register_service_principal.principal;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (register_service_principal.tenant, register_service_principal.principal, register_service_principal.role);
  null;
  return jsonb_build_object('id', register_service_principal.principal, 'tenant', register_service_principal.tenant,
    'name', register_service_principal.name, 'role', register_service_principal.role,
    'isDefault', coalesce(register_service_principal.is_default, false),
    'fields', (select jsonb_build_object('app_note', p."app_note") from "better_supabase"."service_principals" p where p."id" = register_service_principal.principal));
end;
$$;
revoke execute on function "better_supabase"."register_service_principal"(uuid, uuid, text, text, boolean, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."register_service_principal"(uuid, uuid, text, text, boolean, uuid, jsonb) to service_role;

-- Changes a principal's role and its membership. Service role only; with
-- created_by, that member needs the manage permission and may assign role.
create or replace function "better_supabase"."set_service_principal_role"(principal uuid, role text, created_by uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."service_principals";
begin
  select * into v_row from "better_supabase"."service_principals" p where p."id" = set_service_principal_role.principal and p."disabled_at" is null for update;
  if not found then
    raise exception 'No such service principal' using errcode = 'P0002', hint = 'SERVICE_PRINCIPAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if set_service_principal_role.created_by is not null and not (
    coalesce(better_supabase.member_can(set_service_principal_role.created_by, v_row."tenant_id", 'service_accounts.manage'), false)
    and coalesce(better_supabase.can_assign_as(set_service_principal_role.created_by, v_row."tenant_id", set_service_principal_role.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not (set_service_principal_role.role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', set_service_principal_role.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  update "better_supabase"."service_principals" set "role" = set_service_principal_role.role where "id" = v_row."id";
  update "better_supabase"."memberships" set "role" = set_service_principal_role.role
  where "organization_id" = v_row."tenant_id" and "user_id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_service_principal_role"(uuid, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."set_service_principal_role"(uuid, text, uuid) to service_role;

-- Switches a principal off: it loses its membership and stops being the
-- default, so workflow steps and deliveries that resolve to it are refused.
-- The auth.users row stays for the audit trail. Service role only.
create or replace function "better_supabase"."disable_service_principal"(principal uuid, created_by uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."service_principals";
begin
  select * into v_row from "better_supabase"."service_principals" p where p."id" = disable_service_principal.principal and p."disabled_at" is null for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if disable_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(disable_service_principal.created_by, v_row."tenant_id", 'service_accounts.manage'), false)
    and coalesce(better_supabase.can_assign_as(disable_service_principal.created_by, v_row."tenant_id", v_row."role"), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  update "better_supabase"."service_principals" set "disabled_at" = now(), "is_default" = false where "id" = v_row."id";
  delete from "better_supabase"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."disable_service_principal"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."disable_service_principal"(uuid, uuid) to service_role;

-- The tenant's default principal, or null. Workflow builder and webhook
-- delivery resolve organization-owned work to it.
create or replace function "better_supabase"."default_service_principal"(tenant uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p."id" from "better_supabase"."service_principals" p
  where p."tenant_id" = default_service_principal.tenant and p."is_default" and p."disabled_at" is null
$$;
revoke execute on function "better_supabase"."default_service_principal"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."default_service_principal"(uuid) to service_role;

-- The tenant's principals the caller may read, through the read policy.
create or replace function "better_supabase"."service_principals_list"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p."id", 'name', p."name", 'role', p."role", 'isDefault', p."is_default",
    'createdBy', p."created_by", 'createdAt', p."created_at", 'disabledAt', p."disabled_at", 'fields', jsonb_build_object('app_note', p."app_note")
  ) order by p."name"), '[]'::jsonb)
  from "better_supabase"."service_principals" p
  where p."tenant_id" = service_principals_list.tenant
$$;
revoke execute on function "better_supabase"."service_principals_list"(uuid) from public, anon;
grant execute on function "better_supabase"."service_principals_list"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."service_principals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."service_principals";
create policy bsb_tenant_scope_select on "better_supabase"."service_principals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('service_accounts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."service_principals";
create policy bsb_tenant_scope_insert on "better_supabase"."service_principals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."service_principals";
create policy bsb_tenant_scope_update on "better_supabase"."service_principals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."service_principals";
create policy bsb_tenant_scope_delete on "better_supabase"."service_principals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_090_service_accounts.sql
-- better-supabase module: service-accounts
-- @bsb-block-data service-accounts
-- @bsb-hash sha256:2d9091abeb693d8556dc11a1b6b34bbc1e216cb6c5198c9d7c58f6dad7b37ec1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('service-accounts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
