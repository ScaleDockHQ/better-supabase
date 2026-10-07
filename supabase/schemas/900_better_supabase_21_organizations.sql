-- better-supabase module: organizations (0.5.1)
-- @bs-module organizations@1 adopt
-- create_organization(attrs) with slug rules and an after-create hook, a deferred owner check, an assignment ceiling, and member functions (role change, remove, leave, transfer ownership) on the access contract.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- Adopted: "public"."organizations" belongs to the app (modules.organizations.tables.organizations).

-- Why a slug can't be used, or null: 'invalid' (length and pattern from
-- sql.modules.organizations.options), 'reserved' or 'taken'. except_organization skips the
-- organization being renamed.
create or replace function "better_supabase"."organization_slug_problem"(value text, except_organization uuid default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when value is null then null
    when length(value) < 2 or length(value) > 48 or value !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when false then 'reserved'
    when exists (
      select 1 from "public"."organizations" o
      where lower(o."slug"::text) = lower(value)
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
$$;
revoke execute on function "better_supabase"."organization_slug_problem"(text, uuid) from public, anon;
grant execute on function "better_supabase"."organization_slug_problem"(text, uuid) to authenticated, service_role;

-- Creates an organization from attrs (its name, slug and the columns in
-- sql.modules.organizations.options.attributes) and makes the caller its owner. The
-- service role passes the owner as attrs.owner_id.
create or replace function "better_supabase"."create_organization"(attrs jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization uuid;
begin
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', null)
    when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  insert into "public"."organizations" ("name", "slug")
  select r."name", r."slug"
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  returning "id" into organization;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, 'owner');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  
  return organization;
end;
$$;

-- Updates the name, slug and attribute columns present in attrs.
create or replace function "better_supabase"."update_organization"(organization uuid, attrs jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  
  return true;
end;
$$;

-- Deletes an organization (modules.organizations.options.deleteMode: hard, with its memberships).
create or replace function "better_supabase"."delete_organization"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "public"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "public"."memberships" where "organization_id" = organization;
  perform better_supabase.audit_event(
    event_type => 'organization.deleted',
    category => 'organization',
    tenant => organization,
    metadata => jsonb_build_object('mode', 'hard')
  );
  
  return true;
end;
$$;

-- Checked at commit, so one transaction can promote one owner and demote
-- another. An organization may have several owners.
create or replace function "better_supabase"."ensure_organization_owner"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The row lock serializes concurrent demotions and leaves, so two
  -- transactions can't each remove a different last owner.
  perform 1 from "public"."organizations" o where o."id" = old."organization_id" for update;
  if found and not exists (
      select 1 from "public"."memberships" m where m."organization_id" = old."organization_id" and m."role" = 'owner'
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$$;
drop trigger if exists "bs_organization_owner" on "public"."memberships";
create constraint trigger "bs_organization_owner" after update of "role", "organization_id" or delete on "public"."memberships"
  deferrable initially deferred
  for each row execute function "better_supabase"."ensure_organization_owner"();

-- No client grants a role above their own permissions (can_assign), demotes
-- someone above them, or changes their own role. Only writes made as anon or
-- authenticated are checked, like PermDock's assignment triggers: the
-- service role, direct admin connections and security definer functions
-- (the module's own and the app's, which check their own ceilings) pass.
-- The checks, as the module's owner, so the client needs no rights on the
-- roles tables. It only raises, so a direct call reveals nothing.
create or replace function "better_supabase"."guard_membership_role"(target_tenant uuid, target_member uuid, target_role text, previous_tenant uuid, previous_role text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if target_member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(target_tenant, target_role::text)
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, previous_role::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
end;
$$;
revoke execute on function "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) to authenticated, service_role;

-- Security invoker, so current_user is the role that wrote the row.
create or replace function "better_supabase"."guard_membership"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not (current_user in ('anon', 'authenticated')) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new."role" is not distinct from old."role" then
    return new;
  end if;
  perform "better_supabase"."guard_membership_role"(
    new."organization_id", new."user_id", new."role"::text,
    case when tg_op = 'UPDATE' then old."organization_id" end,
    case when tg_op = 'UPDATE' then old."role"::text end
  );
  return new;
end;
$$;
drop trigger if exists "bs_organization_role_guard" on "public"."memberships";
create trigger "bs_organization_role_guard" before insert or update on "public"."memberships"
  for each row execute function "better_supabase"."guard_membership"();
revoke execute on function "better_supabase"."guard_membership"() from public, anon, authenticated;

-- Errors carry a code in the hint: ORGANIZATION_FORBIDDEN, ORGANIZATION_DISABLED, ORGANIZATION_NOT_MEMBER,
-- ORGANIZATION_SELF, ORGANIZATION_SELF_ROLE, ORGANIZATION_ROLE_CEILING, ORGANIZATION_ROLE_UNKNOWN, ORGANIZATION_OWNER_REQUIRED.
create or replace function "better_supabase"."update_member_role"(organization uuid, member uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever sql.modules.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "public"."memberships" set "role" = role
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  
  return true;
end;
$$;

create or replace function "better_supabase"."remove_member"(organization uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  
  return true;
end;
$$;

create or replace function "better_supabase"."leave_organization"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  
  return true;
end;
$$;

-- Makes new_owner an owner in one transaction; a calling owner becomes
-- former_role (modules.organizations.options.formerOwnerRole).
create or replace function "better_supabase"."transfer_ownership"(organization uuid, new_owner uuid, former_role text default 'admin')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me and m."role" = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners (PermDock's transferOnly) sees the transfer as a whole.
  update "public"."memberships" m set "role" = case
      when m."user_id" = new_owner then 'owner'
      else former_role
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and m."role" = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  
  return true;
end;
$$;

-- Records that the caller opened the organization (the last_used_at column of
-- memberships, when it has one), for "recent organizations" lists.
create or replace function "better_supabase"."mark_used"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  update "public"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
$$;

-- Makes organization the caller's active organization (modules.access.activeTenant).
create or replace function "better_supabase"."switch_organization"(organization uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if me is null or not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object('tenant_id', organization::text)
  where id = me;
  update "public"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  
  return jsonb_build_object('organization_id', organization, 'refresh', true);
end;
$$;

revoke execute on function "better_supabase"."create_organization"(jsonb) from public, anon;
grant execute on function "better_supabase"."create_organization"(jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."update_organization"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_organization"(uuid, jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."delete_organization"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_organization"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."update_member_role"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."update_member_role"(uuid, uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."remove_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_member"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."leave_organization"(uuid) from public, anon;
grant execute on function "better_supabase"."leave_organization"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."transfer_ownership"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."transfer_ownership"(uuid, uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."mark_used"(uuid) from public, anon;
grant execute on function "better_supabase"."mark_used"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."switch_organization"(uuid) from public, anon;
grant execute on function "better_supabase"."switch_organization"(uuid) to authenticated, service_role;

-- sql.modules.organizations.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."guard_membership_role"(uuid, uuid, text, uuid, text);

create or replace function "api"."organization_slug_problem"(value text, except_organization uuid default null)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_slug_problem"($1, $2) $$;
revoke execute on function "api"."organization_slug_problem"(text, uuid) from public;
grant execute on function "api"."organization_slug_problem"(text, uuid) to authenticated, service_role;

create or replace function "api"."create_organization"(attrs jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_organization"($1) $$;
revoke execute on function "api"."create_organization"(jsonb) from public;
grant execute on function "api"."create_organization"(jsonb) to authenticated, service_role;

create or replace function "api"."update_organization"(organization uuid, attrs jsonb)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_organization"($1, $2) $$;
revoke execute on function "api"."update_organization"(uuid, jsonb) from public;
grant execute on function "api"."update_organization"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_organization"(organization uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_organization"($1) $$;
revoke execute on function "api"."delete_organization"(uuid) from public;
grant execute on function "api"."delete_organization"(uuid) to authenticated, service_role;

create or replace function "api"."update_member_role"(organization uuid, member uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_member_role"($1, $2, $3) $$;
revoke execute on function "api"."update_member_role"(uuid, uuid, text) from public;
grant execute on function "api"."update_member_role"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."remove_member"(organization uuid, member uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_member"($1, $2) $$;
revoke execute on function "api"."remove_member"(uuid, uuid) from public;
grant execute on function "api"."remove_member"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."leave_organization"(organization uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."leave_organization"($1) $$;
revoke execute on function "api"."leave_organization"(uuid) from public;
grant execute on function "api"."leave_organization"(uuid) to authenticated, service_role;

create or replace function "api"."transfer_ownership"(organization uuid, new_owner uuid, former_role text default 'admin')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."transfer_ownership"($1, $2, $3) $$;
revoke execute on function "api"."transfer_ownership"(uuid, uuid, text) from public;
grant execute on function "api"."transfer_ownership"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."mark_used"(organization uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_used"($1) $$;
revoke execute on function "api"."mark_used"(uuid) from public;
grant execute on function "api"."mark_used"(uuid) to authenticated, service_role;

create or replace function "api"."switch_organization"(organization uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."switch_organization"($1) $$;
revoke execute on function "api"."switch_organization"(uuid) from public;
grant execute on function "api"."switch_organization"(uuid) to authenticated, service_role;

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
