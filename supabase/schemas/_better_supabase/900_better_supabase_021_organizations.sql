-- better-supabase module: organizations
-- @bsb-block organizations@1 managed
-- @bsb-hash sha256:da8e8f1afdee508078557f143f4eb722f8f58f52dab3af28934e7151b30e007b
-- create_organization(attrs) with slug rules and an after-create hook, a deferred owner check, an assignment ceiling, and member functions (role change, remove, leave, transfer ownership) on the access contract.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- public.organizations is the app's table, and it has every column this block needs.
create unique index if not exists organizations_slug_idx on "public"."organizations" (lower("slug"::text));
alter table "public"."organizations" add column if not exists "updated_at" timestamptz not null default now();
-- public.organizations keeps updated_at current with its own trigger organizations_set_updated_at.
alter table "public"."organizations" enable row level security;
grant select on "public"."organizations" to authenticated;
grant all on "public"."organizations" to service_role;
-- public.organizations: the app's policy organizations_member_select already allows what bsb_organizations_select would, so the block adds none.

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
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = lower(value)) then 'reserved'
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
begin
  if not (better_supabase.actor_may_write()) then
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
  values (organization, owner, (select r."id" from "better_supabase"."roles" r where (r."id"::text = ('owner')::text or r."key" = ('owner')::text) order by (r."id"::text = ('owner')::text) desc limit 1));
  perform "better_supabase"."seed_tenant_defaults"(organization);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  perform "better_supabase".emit_event('organization.created', jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
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
  if not (better_supabase.actor_may_write()) then
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
    v_hook regprocedure := to_regprocedure('"public"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  perform "better_supabase".emit_event('organization.updated', jsonb_build_object('organizationId', organization::text, 'userId', auth.uid()), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
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

-- Deletes an organization (blocks.organizations.options.deleteMode: hard, with its memberships).
create or replace function "better_supabase"."delete_organization"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "public"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "public"."memberships" where "organization_id" = organization;
  perform "better_supabase".emit_event('organization.deleted', jsonb_build_object('organizationId', organization::text, 'userId', auth.uid()), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
  perform better_supabase.audit_event(
    event_type => 'organization.deleted',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
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
      select 1 from "public"."memberships" m where m."organization_id" = old."organization_id" and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ensure_organization_owner"() from public, anon, authenticated;
create constraint trigger "bsb_organization_owner" after update of "role", "organization_id" or delete on "public"."memberships"
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
create trigger "bsb_organization_role_guard" before insert or update on "public"."memberships"
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) order by (r."id"::text = (role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role"), m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever blocks.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and coalesce(member = auth.uid(), false) then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) order by (r."id"::text = (role)::text) desc limit 1))::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) order by (r."id"::text = (role)::text) desc limit 1)
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  perform "better_supabase".emit_event('organization.role_changed', jsonb_build_object('organizationId', organization::text, 'userId', member, 'role', role, 'previousRole', previous), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  perform "better_supabase".emit_event('organization.member_removed', jsonb_build_object('organizationId', organization::text, 'userId', member), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  perform "better_supabase".emit_event('organization.member_left', jsonb_build_object('organizationId', organization::text, 'userId', me), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (former_role)::text or r."key" = (former_role)::text) order by (r."id"::text = (former_role)::text) desc limit 1) is not null) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners sees the transfer as a whole.
  update "public"."memberships" m set "role" = case
      when m."user_id" = new_owner then (select r."id" from "better_supabase"."roles" r where (r."id"::text = ('owner')::text or r."key" = ('owner')::text) order by (r."id"::text = ('owner')::text) desc limit 1)
      else (select r."id" from "better_supabase"."roles" r where (r."id"::text = (former_role)::text or r."key" = (former_role)::text) order by (r."id"::text = (former_role)::text) desc limit 1)
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  perform "better_supabase".emit_event('organization.ownership_transferred', jsonb_build_object('organizationId', organization::text, 'userId', new_owner, 'role', 'owner'), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "public"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
$$;

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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
  perform "better_supabase".emit_event('organization.switched', jsonb_build_object('organizationId', organization::text, 'userId', me), 'organizations/' || organization::text, (organization)::text, null, 'better-supabase/organizations');
  return jsonb_build_object('organization_id', organization, 'refresh', true);
end;
$$;
create or replace function "better_supabase"."list_my_organizations"()
returns table (
  id uuid,
  name text,
  slug text,
  role text
)
language sql
stable
security definer
set search_path = ''
as $$
  select o."id", o."name", o."slug", m."role"::text
  from "public"."memberships" m
  join "public"."organizations" o on o."id" = m."organization_id"
  where m."user_id" = (select auth.uid())
    and not better_supabase.tenant_disabled(o."id")
  order by o."name"
$$;
create or replace function "better_supabase"."list_members"(organization uuid)
returns table (user_id uuid, role text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m."user_id", m."role"::text
  from "public"."memberships" m
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
  select i."id", i."email", i."role"::text, i."expires_at"
  from "better_supabase"."invitations" i
  where i."tenant_id" = organization and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null and i."expires_at" >= now()
  order by i."expires_at" desc;
end;
$$;

-- The organization page in one call. It runs as the caller and reads through
-- the listing functions, so the permissions to list members and invitations
-- apply. Seats come from billing_status and are null when the caller may not
-- read billing.
create or replace function "better_supabase"."organization_overview"(organization uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from "better_supabase"."list_my_organizations"() o
  where o.id = organization_overview.organization;
  if v_org is null then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from "better_supabase"."list_members"(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id, 'email', i.email, 'role', i.role, 'expiresAt', to_jsonb(i) -> 'expires_at')
          order by i.email)
        from "better_supabase"."list_organization_invitations"(organization_overview.organization) i
      ), '[]'::jsonb)
  );
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
revoke execute on function "better_supabase"."organization_overview"(uuid) from public, anon;
grant execute on function "better_supabase"."organization_overview"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_organization_invitations"(uuid) from public, anon;
grant execute on function "better_supabase"."list_organization_invitations"(uuid) to authenticated, service_role;

create table "better_supabase"."organization_profiles" (
  "tenant_id" uuid primary key,
  "vat_id" text,
  "registration_id" text,
  "default_rate" numeric,
  "currency" text,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."organization_profiles" enable row level security;
revoke all on "better_supabase"."organization_profiles" from public, anon, authenticated;
grant select on "better_supabase"."organization_profiles" to authenticated;
grant all on "better_supabase"."organization_profiles" to service_role;
create policy bsb_organization_profiles_read on "better_supabase"."organization_profiles"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create table "better_supabase"."organization_payment_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "iban" text not null,
  "bic" text,
  "holder" text,
  "label" text,
  "is_primary" boolean not null default false,
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "iban")
);
create unique index organization_payment_accounts_primary_idx
  on "better_supabase"."organization_payment_accounts" ("tenant_id") where "is_primary";
alter table "better_supabase"."organization_payment_accounts" enable row level security;
revoke all on "better_supabase"."organization_payment_accounts" from public, anon, authenticated;
grant select on "better_supabase"."organization_payment_accounts" to authenticated;
grant all on "better_supabase"."organization_payment_accounts" to service_role;
create policy bsb_organization_payment_accounts_read on "better_supabase"."organization_payment_accounts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- The organization's VAT, registration, default rate, currency and payment
-- accounts. An IBAN matches on a repeat import. A missing value leaves the
-- stored one, and the stored primary account stays unless an account says
-- isPrimary. A VAT number that is only a country prefix is skipped.
create or replace function "better_supabase"."import_organization_profile"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_organization_profile.item -> 'data';
  v_tenant uuid := (import_organization_profile.item ->> 'tenant')::uuid;
  v_vat text := nullif(upper(btrim(v_data ->> 'vatId')), '');
  v_warnings jsonb := '[]'::jsonb;
  v_account jsonb;
  v_iban text;
  v_primary boolean;
  v_id uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'an organization profile needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_vat ~ '^[A-Z]{2}$' then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_VAT_PREFIX', 'message', 'a VAT number that is only a country prefix was skipped'));
    v_vat := null;
  end if;
  insert into "better_supabase"."organization_profiles" ("tenant_id") values (v_tenant) on conflict ("tenant_id") do nothing;
  if exists (
    select 1 from "better_supabase"."organization_profiles" x
    where x."tenant_id" = v_tenant
      and (v_vat is null or x."vat_id" is not distinct from v_vat)
      and (v_data ->> 'registrationId' is null or x."registration_id" is not distinct from nullif(btrim(v_data ->> 'registrationId'), ''))
      and (v_data ->> 'defaultRate' is null or x."default_rate" is not distinct from (v_data ->> 'defaultRate')::numeric)
      and (v_data ->> 'currency' is null or x."currency" is not distinct from nullif(btrim(v_data ->> 'currency'), ''))
  ) then
    v_updated := (select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id" = v_tenant);
  else
    update "better_supabase"."organization_profiles" x set
      "vat_id" = coalesce(v_vat, x."vat_id"),
      "registration_id" = coalesce(nullif(btrim(v_data ->> 'registrationId'), ''), x."registration_id"),
      "default_rate" = coalesce((v_data ->> 'defaultRate')::numeric, x."default_rate"),
      "currency" = coalesce(nullif(btrim(v_data ->> 'currency'), ''), x."currency"),
      "updated_at" = now()
    where x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  if jsonb_typeof(v_data -> 'accounts') = 'array' then
    for v_account in select value from jsonb_array_elements(v_data -> 'accounts') loop
      v_iban := upper(regexp_replace(coalesce(v_account ->> 'iban', ''), '\s', '', 'g'));
      if not better_supabase.validate_iban(v_iban) then
        raise exception 'a payment account needs a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
      v_primary := case when v_account ? 'isPrimary' then (v_account ->> 'isPrimary')::boolean else null end;
      select x."id" into v_id from "better_supabase"."organization_payment_accounts" x
      where x."tenant_id" = v_tenant and x."iban" = v_iban
        and x."bic" is not distinct from coalesce(nullif(upper(btrim(v_account ->> 'bic')), ''), x."bic")
        and x."holder" is not distinct from coalesce(nullif(btrim(v_account ->> 'holder'), ''), x."holder")
        and x."label" is not distinct from coalesce(nullif(btrim(v_account ->> 'label'), ''), x."label")
        and (v_primary is null or x."is_primary" = v_primary);
      if v_id is null then
        if v_primary is true then
          update "better_supabase"."organization_payment_accounts" x set "is_primary" = false where x."tenant_id" = v_tenant and x."iban" <> v_iban;
        end if;
        insert into "better_supabase"."organization_payment_accounts" ("tenant_id", "iban", "bic", "holder", "label", "is_primary")
        values (v_tenant, v_iban, nullif(upper(btrim(v_account ->> 'bic')), ''), nullif(btrim(v_account ->> 'holder'), ''),
          nullif(btrim(v_account ->> 'label'), ''), coalesce(v_primary, false))
        on conflict ("tenant_id", "iban") do update set
          "bic" = coalesce(excluded."bic", "better_supabase"."organization_payment_accounts"."bic"),
          "holder" = coalesce(excluded."holder", "better_supabase"."organization_payment_accounts"."holder"),
          "label" = coalesce(excluded."label", "better_supabase"."organization_payment_accounts"."label"),
          "is_primary" = case when v_primary is true then true else "better_supabase"."organization_payment_accounts"."is_primary" end,
          "updated_at" = now();
      end if;
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_tenant, 'updatedAt', coalesce(v_updated, now()), 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_organization_profile"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_organization_profile"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."organization_profile_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id"::text = organization_profile_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."organization_profile_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."organization_profile_updated_at"(text) to service_role;

-- blocks.organizations.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."organization_slug_problem"(value text, except_organization uuid default null)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_slug_problem"($1, $2) $$;
revoke execute on function "api"."organization_slug_problem"(text, uuid) from public, anon;
grant execute on function "api"."organization_slug_problem"(text, uuid) to authenticated, service_role;

create or replace function "api"."create_organization"(attrs jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_organization"($1) $$;
revoke execute on function "api"."create_organization"(jsonb) from public, anon;
grant execute on function "api"."create_organization"(jsonb) to authenticated, service_role;

create or replace function "api"."update_organization"(organization uuid, attrs jsonb)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_organization"($1, $2) $$;
revoke execute on function "api"."update_organization"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_organization"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_organization"(organization uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_organization"($1) $$;
revoke execute on function "api"."delete_organization"(uuid) from public, anon;
grant execute on function "api"."delete_organization"(uuid) to authenticated, service_role;

create or replace function "api"."update_member_role"(organization uuid, member uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_member_role"($1, $2, $3) $$;
revoke execute on function "api"."update_member_role"(uuid, uuid, text) from public, anon;
grant execute on function "api"."update_member_role"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."remove_member"(organization uuid, member uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_member"($1, $2) $$;
revoke execute on function "api"."remove_member"(uuid, uuid) from public, anon;
grant execute on function "api"."remove_member"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."leave_organization"(organization uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."leave_organization"($1) $$;
revoke execute on function "api"."leave_organization"(uuid) from public, anon;
grant execute on function "api"."leave_organization"(uuid) to authenticated, service_role;

create or replace function "api"."transfer_ownership"(organization uuid, new_owner uuid, former_role text default 'admin')
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."transfer_ownership"($1, $2, $3) $$;
revoke execute on function "api"."transfer_ownership"(uuid, uuid, text) from public, anon;
grant execute on function "api"."transfer_ownership"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."mark_used"(organization uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_used"($1) $$;
revoke execute on function "api"."mark_used"(uuid) from public, anon;
grant execute on function "api"."mark_used"(uuid) to authenticated, service_role;

create or replace function "api"."switch_organization"(organization uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."switch_organization"($1) $$;
revoke execute on function "api"."switch_organization"(uuid) from public, anon;
grant execute on function "api"."switch_organization"(uuid) to authenticated, service_role;

create or replace function "api"."list_my_organizations"()
returns table (
  id uuid,
  name text,
  slug text,
  role text
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_my_organizations"() $$;
revoke execute on function "api"."list_my_organizations"() from public, anon;
grant execute on function "api"."list_my_organizations"() to authenticated, service_role;

create or replace function "api"."list_members"(organization uuid)
returns table (user_id uuid, role text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_members"($1) $$;
revoke execute on function "api"."list_members"(uuid) from public, anon;
grant execute on function "api"."list_members"(uuid) to authenticated, service_role;

create or replace function "api"."organization_overview"(organization uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_overview"($1) $$;
revoke execute on function "api"."organization_overview"(uuid) from public, anon;
grant execute on function "api"."organization_overview"(uuid) to authenticated, service_role;

create or replace function "api"."list_organization_invitations"(organization uuid)
returns table (
  id uuid,
  email text,
  role text,
  expires_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."list_organization_invitations"($1) $$;
revoke execute on function "api"."list_organization_invitations"(uuid) from public, anon;
grant execute on function "api"."list_organization_invitations"(uuid) to authenticated, service_role;

create or replace function "api"."import_organization_profile"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_organization_profile"($1, $2, $3) $$;
revoke execute on function "api"."import_organization_profile"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_organization_profile"(uuid, jsonb, text) to service_role;

create or replace function "api"."organization_profile_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_profile_updated_at"($1) $$;
revoke execute on function "api"."organization_profile_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."organization_profile_updated_at"(text) to service_role;
