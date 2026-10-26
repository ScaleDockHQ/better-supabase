-- better-supabase module: teams
-- @bsb-block teams@2 managed
-- @bsb-hash sha256:3a37649446b4bfa2ffd1e62e39af9fb9ea22f91eb0d4e504c3cf98b6f790d1f6
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
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
    drop policy if exists bsb_tenant_scope on "centrakit"."teams";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."teams";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."teams";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."teams";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."teams";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "centrakit"."team_members";
    drop policy if exists bsb_tenant_scope_select on "centrakit"."team_members";
    drop policy if exists bsb_tenant_scope_insert on "centrakit"."team_members";
    drop policy if exists bsb_tenant_scope_update on "centrakit"."team_members";
    drop policy if exists bsb_tenant_scope_delete on "centrakit"."team_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
-- centrakit.teams is the app's table, and it has every column this block needs.
alter table "centrakit"."teams" enable row level security;
grant select on "centrakit"."teams" to authenticated;
grant all on "centrakit"."teams" to service_role;
drop policy if exists bsb_teams_select on "centrakit"."teams";
create policy bsb_teams_select on "centrakit"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

-- centrakit.team_members is the app's table, and it has every column this block needs.
create index if not exists team_members_user_idx on "centrakit"."team_members" ("user_id");
create index if not exists team_members_membership_idx on "centrakit"."team_members" ("tenant_id", "user_id");
alter table "centrakit"."team_members" enable row level security;
grant select on "centrakit"."team_members" to authenticated;
grant all on "centrakit"."team_members" to service_role;
drop policy if exists bsb_team_members_select on "centrakit"."team_members";
create policy bsb_team_members_select on "centrakit"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "better_supabase"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "centrakit"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (blocks.teams.options.extraColumns) to set.
drop function if exists "better_supabase"."create_team"(uuid, text, text, jsonb);
create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "centrakit"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('team.created', jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name), 'teams/' || (v_id)::text, (create_team.tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'team.created',
    category => 'membership',
    target_type => 'team',
    record_id => (v_id)::text,
    tenant => (create_team.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."update_team"(uuid, text, text, jsonb);
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "centrakit"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "centrakit"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  perform "better_supabase".emit_event('team.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name), 'teams/' || (update_team.team)::text, (v_tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return jsonb_build_object('id', update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "centrakit"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "centrakit"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  perform "better_supabase".emit_event('team.archived', jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team), 'teams/' || (archive_team.team)::text, (v_tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'team.archived',
    category => 'membership',
    target_type => 'team',
    record_id => (archive_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_team"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_team"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."delete_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "centrakit"."teams" where "id" = delete_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "centrakit"."teams" where "id" = delete_team.team;
  perform "better_supabase".emit_event('team.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_team.team), 'teams/' || (delete_team.team)::text, (v_tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'team.deleted',
    category => 'membership',
    target_type => 'team',
    record_id => (delete_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', delete_team.team)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_team"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_team"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."add_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "centrakit"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "centrakit"."organization_users" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "centrakit"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  perform "better_supabase".emit_event('team_member.added', jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', add_team_member.member), 'teams/' || (add_team_member.team)::text, (v_tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'team_member.added',
    category => 'membership',
    target_type => 'team',
    record_id => (add_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', add_team_member.member)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "centrakit"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "centrakit"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  perform "better_supabase".emit_event('team_member.removed', jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', remove_team_member.member), 'teams/' || (remove_team_member.team)::text, (v_tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'team_member.removed',
    category => 'membership',
    target_type => 'team',
    record_id => (remove_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', remove_team_member.member)
  );
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_teams"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t."id",
    'name', t."name",
    'slug', t."slug",
    'status', t."status"
  )), '[]'::jsonb)
  from "centrakit"."teams" t
  where t."tenant_id" = list_teams.tenant
    and (
      auth.role() = 'service_role'
      or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)
    )
$$;
revoke execute on function "better_supabase"."list_teams"(uuid) from public, anon;
grant execute on function "better_supabase"."list_teams"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "centrakit"."teams";
drop policy if exists bsb_tenant_scope_select on "centrakit"."teams";
create policy bsb_tenant_scope_select on "centrakit"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "centrakit"."teams";
create policy bsb_tenant_scope_insert on "centrakit"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "centrakit"."teams";
create policy bsb_tenant_scope_update on "centrakit"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "centrakit"."teams";
create policy bsb_tenant_scope_delete on "centrakit"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "centrakit"."team_members";
drop policy if exists bsb_tenant_scope_select on "centrakit"."team_members";
create policy bsb_tenant_scope_select on "centrakit"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "centrakit"."team_members";
create policy bsb_tenant_scope_insert on "centrakit"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "centrakit"."team_members";
create policy bsb_tenant_scope_update on "centrakit"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "centrakit"."team_members";
create policy bsb_tenant_scope_delete on "centrakit"."team_members" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
