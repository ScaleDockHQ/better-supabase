-- better-supabase module: organizations
-- @bsb-block organizations@1 managed
-- @bsb-hash sha256:6abbbf4f63949ffe9b1f8317c98770d074fe62d02cec335c1c0eb8977eb8d47e
-- create_organization(attrs) with slug rules and an after-create hook, a deferred owner check, an assignment ceiling, and member functions (role change, remove, leave, transfer ownership) on the access contract.
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

-- centrakit.organizations is the app's table, and it has every column this block needs.
create unique index if not exists organizations_slug_idx on "centrakit"."organizations" (lower("slug"::text));
alter table "centrakit"."organizations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "centrakit"."organizations";
create trigger bsb_updated_at before update on "centrakit"."organizations"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "centrakit"."organizations" enable row level security;
grant select on "centrakit"."organizations" to authenticated;
grant all on "centrakit"."organizations" to service_role;
drop policy if exists bsb_organizations_read on "centrakit"."organizations";
drop policy if exists bsb_organizations_select on "centrakit"."organizations";
create policy bsb_organizations_select on "centrakit"."organizations"
  for select to authenticated
  using ("id" in (select better_supabase.member_organization_ids()));

-- Why a slug can't be used, or null: 'invalid' (length and pattern from
-- blocks.organizations.options), 'reserved' or 'taken'. except_organization skips the
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
    when lower(value) = any (array['app', 'admin']::text[]) then 'reserved'
    when exists (
      select 1 from "centrakit"."organizations" o
      where lower(o."slug"::text) = lower(value)
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
$$;
revoke execute on function "better_supabase"."organization_slug_problem"(text, uuid) from public, anon;
grant execute on function "better_supabase"."organization_slug_problem"(text, uuid) to authenticated, service_role;

-- Creates an organization from attrs (its name, slug and the columns in
-- blocks.organizations.options.attributes) and makes the caller its owner. The
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
  extra_columns text;
  extra_values text;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    v_hook regprocedure := to_regprocedure('"centrakit"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  select coalesce(string_agg(format(', %I', c), ''), ''), coalesce(string_agg(format(', r.%I', c), ''), '')
  into extra_columns, extra_values
  from unnest(array['website', 'logo_path', 'default_currency']) c
  where attrs ? c;
  execute format(
    'insert into "centrakit"."organizations" ("name", "slug"%s) select r."name", r."slug"%s from jsonb_populate_record(null::"centrakit"."organizations", $1) r returning "id"',
    extra_columns,
    extra_values
  ) into organization using attrs, owner;
  insert into "centrakit"."organization_users" ("organization_id", "user_id", "role_id")
  values (organization, owner, (select r."id" from "centrakit"."roles" r where (r."id"::text = ('owner')::text or r."key"::text = ('owner')::text) and (r.scope = 'organization') order by (r."id"::text = ('owner')::text) desc limit 1));
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."seed_organization"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  perform "better_supabase".emit_event('organization.created', jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.created',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner')
  );
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "centrakit"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end,
    "website" = case when attrs ? 'website' then r."website" else o."website" end,
    "logo_path" = case when attrs ? 'logo_path' then r."logo_path" else o."logo_path" end,
    "default_currency" = case when attrs ? 'default_currency' then r."default_currency" else o."default_currency" end
  from jsonb_populate_record(null::"centrakit"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  perform "better_supabase".emit_event('organization.updated', jsonb_build_object('organizationId', organization::text, 'userId', auth.uid()), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.updated',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', auth.uid())
  );
  return true;
end;
$$;

-- Deletes an organization through data-lifecycle (blocks.organizations.options.deleteMode
-- "lifecycle"): schedules the purge after the grace period and disables it.
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
  perform "better_supabase"."request_organization_deletion"(organization);
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
  perform 1 from "centrakit"."organizations" o where o."id" = old."organization_id" for update;
  if found and not exists (
      select 1 from "centrakit"."organization_users" m where m."organization_id" = old."organization_id" and (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) = 'owner'
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ensure_organization_owner"() from public, anon, authenticated;
drop trigger if exists "bsb_organization_owner" on "centrakit"."organization_users";
create constraint trigger "bsb_organization_owner" after update of "role_id", "organization_id" or delete on "centrakit"."organization_users"
  deferrable initially deferred
  for each row execute function "better_supabase"."ensure_organization_owner"();

-- No client grants a role above their own permissions (can_assign), demotes
-- someone above them, or changes their own role. Only writes made as anon or
-- authenticated are checked: the service role, direct admin connections and
-- security definer functions (the module's own and the app's, which check
-- their own ceilings) pass.
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
  if not better_supabase.can_assign(target_tenant, (select r."key"::text from "centrakit"."roles" r where r."id"::text = (target_role)::text))
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, (select r."key"::text from "centrakit"."roles" r where r."id"::text = (previous_role)::text))) then
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
  if tg_op = 'UPDATE' and new."role_id" is not distinct from old."role_id" then
    return new;
  end if;
  perform "better_supabase"."guard_membership_role"(
    new."organization_id", new."user_id", new."role_id"::text,
    case when tg_op = 'UPDATE' then old."organization_id" end,
    case when tg_op = 'UPDATE' then old."role_id"::text end
  );
  return new;
end;
$$;
drop trigger if exists "bsb_organization_role_guard" on "centrakit"."organization_users";
create trigger "bsb_organization_role_guard" before insert or update on "centrakit"."organization_users"
  for each row execute function "better_supabase"."guard_membership"();
revoke execute on function "better_supabase"."guard_membership"() from public, anon, authenticated;

-- Errors carry a code in the hint: ORGANIZATION_FORBIDDEN, ORGANIZATION_DISABLED, ORGANIZATION_NOT_MEMBER,
-- ORGANIZATION_SELF, ORGANIZATION_SELF_ROLE, ORGANIZATION_ROLE_CEILING, ORGANIZATION_ROLE_UNKNOWN, ORGANIZATION_OWNER_REQUIRED,
-- ORGANIZATION_ROLE_LAST.
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "centrakit"."organizations" o where o."id" = organization and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not ((select r."id" from "centrakit"."roles" r where (r."id"::text = (role)::text or r."key"::text = (role)::text) and (r.scope = 'organization') order by (r."id"::text = (role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text), (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) into previous, previous_assignable
  from "centrakit"."organization_users" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever blocks.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (select r."key"::text from "centrakit"."roles" r where r."id"::text = (((select r."id" from "centrakit"."roles" r where (r."id"::text = (role)::text or r."key"::text = (role)::text) and (r.scope = 'organization') order by (r."id"::text = (role)::text) desc limit 1)))::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "centrakit"."organization_users" set "role_id" = (select r."id" from "centrakit"."roles" r where (r."id"::text = (role)::text or r."key"::text = (role)::text) and (r.scope = 'organization') order by (r."id"::text = (role)::text) desc limit 1)
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  perform "better_supabase".emit_event('organization.role_changed', jsonb_build_object('organizationId', organization::text, 'userId', member, 'role', role, 'previousRole', previous), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.role_changed',
    category => 'membership',
    target_type => 'user',
    record_id => member::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', member, 'role', role, 'previousRole', previous)
  );
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) into current_role_value from "centrakit"."organization_users" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "centrakit"."organization_users" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  perform "better_supabase".emit_event('organization.member_removed', jsonb_build_object('organizationId', organization::text, 'userId', member), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.member_removed',
    category => 'membership',
    target_type => 'user',
    record_id => member::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', member)
  );
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "centrakit"."organization_users" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  perform "better_supabase".emit_event('organization.member_left', jsonb_build_object('organizationId', organization::text, 'userId', me), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.member_left',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', me)
  );
  return true;
end;
$$;

-- Makes new_owner an owner in one transaction; a calling owner becomes
-- former_role (blocks.organizations.options.formerOwnerRole).
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "centrakit"."organization_users" m where m."organization_id" = organization and m."user_id" = me and (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "centrakit"."organizations" o where o."id" = organization and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not ((select r."id" from "centrakit"."roles" r where (r."id"::text = (former_role)::text or r."key"::text = (former_role)::text) and (r.scope = 'organization') order by (r."id"::text = (former_role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "centrakit"."organization_users" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners sees the transfer as a whole.
  update "centrakit"."organization_users" m set "role_id" = case
      when m."user_id" = new_owner then (select r."id" from "centrakit"."roles" r where (r."id"::text = ('owner')::text or r."key"::text = ('owner')::text) and (r.scope = 'organization') order by (r."id"::text = ('owner')::text) desc limit 1)
      else (select r."id" from "centrakit"."roles" r where (r."id"::text = (former_role)::text or r."key"::text = (former_role)::text) and (r.scope = 'organization') order by (r."id"::text = (former_role)::text) desc limit 1)
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"centrakit"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  perform "better_supabase".emit_event('organization.ownership_transferred', jsonb_build_object('organizationId', organization::text, 'userId', new_owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.ownership_transferred',
    category => 'membership',
    target_type => 'user',
    record_id => new_owner::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', new_owner, 'role', 'owner')
  );
  return true;
end;
$$;


drop function if exists "better_supabase"."add_member_role"(uuid, uuid, text);
drop function if exists "better_supabase"."remove_member_role"(uuid, uuid, text);

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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "centrakit"."organization_users" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
$$;

drop function if exists "better_supabase"."suspend_member"(uuid, uuid);
drop function if exists "better_supabase"."resume_member"(uuid, uuid);

-- Makes organization the caller's active organization (blocks.permissions.activeTenant).
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null or not exists (select 1 from "centrakit"."organization_users" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "centrakit"."organizations" o where o."id" = organization and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  update "centrakit"."profiles" set "active_organization_id" = organization where "user_id" = me;
  update "centrakit"."organization_users" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  perform "better_supabase".emit_event('organization.switched', jsonb_build_object('organizationId', organization::text, 'userId', me), 'organizations/' || organization::text, (organization)::text, null, 'domain');
  return jsonb_build_object('organization_id', organization, 'refresh', false);
end;
$$;

drop function if exists "better_supabase"."list_my_organizations"();
create or replace function "better_supabase"."list_my_organizations"()
returns table (
  id uuid,
  name text,
  slug text,
  role text,
  attributes jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select o."id", o."name", o."slug", m."role_id"::text, jsonb_build_object('website', o."website", 'logo_path', o."logo_path", 'default_currency', o."default_currency")
  from "centrakit"."organization_users" m
  join "centrakit"."organizations" o on o."id" = m."organization_id"
  where m."user_id" = (select auth.uid()) and o."disabled_at" is null
    and not better_supabase.tenant_disabled(o."id")
  order by o."name"
$$;

drop function if exists "better_supabase"."list_members"(uuid);
create or replace function "better_supabase"."list_members"(organization uuid)
returns table (user_id uuid, role text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'people.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m."user_id", m."role_id"::text
  from "centrakit"."organization_users" m
  where m."organization_id" = organization
  order by m."user_id";
end;
$$;

create or replace function "better_supabase"."list_organization_invitations"(organization uuid)
returns table (
  id uuid,
  email text,
  role text,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.invite'), false) then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select i."id", i."email", i."role_id"::text, i."expires_at"
  from "centrakit"."organization_invitations" i
  where i."organization_id" = organization and i."accepted_at" is null and i."declined_at" is null and i."expires_at" >= now()
  order by i."expires_at" desc;
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
revoke execute on function "better_supabase"."list_my_organizations"() from public, anon;
grant execute on function "better_supabase"."list_my_organizations"() to authenticated, service_role;
revoke execute on function "better_supabase"."list_members"(uuid) from public, anon;
grant execute on function "better_supabase"."list_members"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_organization_invitations"(uuid) from public, anon;
grant execute on function "better_supabase"."list_organization_invitations"(uuid) to authenticated, service_role;

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
