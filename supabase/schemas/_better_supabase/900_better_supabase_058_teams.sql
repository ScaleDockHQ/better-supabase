-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:5e45d32e51fd835e548dd80966b211c95b03e907111256e8b5cbd76feca7a9aa
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid references auth.users (id) on delete cascade,
  "employee_id" uuid,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  constraint bsb_team_members_check check ("user_id" is not null or "employee_id" is not null)
);
create unique index "bsb_team_members_user_key" on "better_supabase"."team_members" ("team_id", "user_id") where "user_id" is not null;
create unique index "bsb_team_members_employee_key" on "better_supabase"."team_members" ("team_id", "employee_id") where "employee_id" is not null;
create index team_members_employee_idx on "better_supabase"."team_members" ("employee_id") where "employee_id" is not null;
create index team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "public"."memberships" ("organization_id", "user_id")
  on delete cascade;

alter table "better_supabase"."inbox_conversations"
  add constraint conversations_team_fkey
  foreign key ("team_id") references "better_supabase"."teams" ("id") on delete set null;
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
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text, slug text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := coalesce(create_team.slug, trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g')));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' or (create_team.slug is not null and create_team.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$') then
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
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('team.created', jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name), 'teams/' || (v_id)::text, (create_team.tenant)::text, null, 'better-supabase/teams');
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
revoke execute on function "better_supabase"."create_team"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text, text) to authenticated, service_role;
-- patch: name, slug and description to set; a key that is present sets its
-- column, so null clears the description.
create or replace function "better_supabase"."update_team"(team uuid, name text, description text, patch jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if update_team.patch is not null and (jsonb_typeof(update_team.patch) <> 'object'
    or update_team.patch ? 'slug' and coalesce(update_team.patch ->> 'slug', '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    or update_team.patch ? 'name' and nullif(trim(update_team.patch ->> 'name'), '') is null) then
    raise exception 'patch sets name, slug or description; name and slug can''t be empty' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.patch ->> 'name', update_team.name, t."name"),
      "slug" = case when update_team.patch ? 'slug' then update_team.patch ->> 'slug' else t."slug" end,
      "description" = case when update_team.patch ? 'description' then update_team.patch ->> 'description' else coalesce(update_team.description, t."description") end,
      "updated_at" = now()
  where t."id" = update_team.team;
  perform "better_supabase".emit_event('team.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name), 'teams/' || (update_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  perform "better_supabase".emit_event('team.archived', jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team), 'teams/' || (archive_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
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

create or replace function "better_supabase"."restore_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = restore_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'active', "updated_at" = now() where "id" = restore_team.team;
  perform "better_supabase".emit_event('team.restored', jsonb_build_object('organizationId', v_tenant, 'id', restore_team.team), 'teams/' || (restore_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.restored',
    category => 'membership',
    target_type => 'team',
    record_id => (restore_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', restore_team.team)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."restore_team"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_team"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."delete_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = delete_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = delete_team.team;
  perform "better_supabase".emit_event('team.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_team.team), 'teams/' || (delete_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
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

-- A row whose employee stays (the team and the employee exist) keeps the
-- employee when its user loses the account or the tenant membership.
create or replace function better_supabase.bsb_team_member_employee_keep()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old."employee_id" is null or old."user_id" is null
    or not exists (select 1 from "better_supabase"."teams" t where t."id" = old."team_id")
    or not exists (select 1 from "better_supabase"."employees" x where x."id" = old."employee_id")
    or (exists (select 1 from auth.users u where u.id = old."user_id")
      and exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = old."tenant_id"
      and m."user_id" = old."user_id"
  )) then
    return old;
  end if;
  update "better_supabase"."team_members" set "user_id" = null
  where "team_id" = old."team_id" and "employee_id" = old."employee_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_team_member_employee_keep() from public, anon, authenticated;
create trigger bsb_team_member_employee_keep before delete on "better_supabase"."team_members"
for each row execute function better_supabase.bsb_team_member_employee_keep();
-- member: a user id; employee: an employee id. Pass one of them.
create or replace function "better_supabase"."add_team_member"(team uuid, member uuid default null, employee uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_user uuid := add_team_member.member;
  v_employee uuid := add_team_member.employee;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if (add_team_member.member is null) = (add_team_member.employee is null) then
    raise exception 'pass either a user or an employee' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  if v_employee is null then
    if not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = v_user
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
    v_employee := (
      select x."id" from "better_supabase"."employees" x
      where x."tenant_id" = v_tenant and x."user_id" = v_user
    );
  else
    select x."user_id" into v_user from "better_supabase"."employees" x
    where x."id" = v_employee and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'employee is not in the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
    end if;
    if v_user is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = v_user
  ) then
      v_user := null;
    end if;
  end if;
  if v_employee is not null and v_user is not null then
    delete from "better_supabase"."team_members" x
    where x."team_id" = add_team_member.team and x."user_id" = v_user and x."employee_id" is null
      and exists (
        select 1 from "better_supabase"."team_members" y
        where y."team_id" = add_team_member.team and y."employee_id" = v_employee
      );
    update "better_supabase"."team_members" set "user_id" = v_user
    where "team_id" = add_team_member.team and "employee_id" = v_employee and "user_id" is null;
    update "better_supabase"."team_members" set "employee_id" = v_employee
    where "team_id" = add_team_member.team and "user_id" = v_user and "employee_id" is null;
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
  values (add_team_member.team, v_user, v_employee, v_tenant)
  on conflict do nothing;
  perform "better_supabase".emit_event('team_member.added', jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', v_user, 'employeeId', v_employee), 'teams/' || (add_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.added',
    category => 'membership',
    target_type => 'team',
    record_id => (add_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', v_user, 'employeeId', v_employee)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid, uuid) to authenticated, service_role;
-- member: a user id; employee: an employee id. Pass one of them. Removing a
-- user whose row has an employee removes the employee too.
create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid default null, employee uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_user uuid;
  v_employee uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if (remove_team_member.member is null) = (remove_team_member.employee is null) then
    raise exception 'pass either a user or an employee' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  delete from "better_supabase"."team_members" x
  where x."team_id" = remove_team_member.team
    and (x."employee_id" = remove_team_member.employee or x."user_id" = remove_team_member.member)
  returning x."user_id", x."employee_id" into v_user, v_employee;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('team_member.deleted', jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', v_user, 'employeeId', v_employee), 'teams/' || (remove_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.deleted',
    category => 'membership',
    target_type => 'team',
    record_id => (remove_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', v_user, 'employeeId', v_employee)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid, uuid) to authenticated, service_role;

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
    'description', t."description",
    'status', t."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb)
  ) order by t."name"), '[]'::jsonb)
  from "better_supabase"."teams" t
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
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.teams deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"team","event_prefix":"team"}');

-- blocks.teams.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."team_ids_of"(member uuid)
returns setof uuid
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."team_ids_of"($1) $$;
revoke execute on function "api"."team_ids_of"(uuid) from public, anon;
grant execute on function "api"."team_ids_of"(uuid) to authenticated, service_role;

create or replace function "api"."create_team"(tenant uuid, name text, description text, slug text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_team"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_team"(uuid, text, text, text) from public, anon;
grant execute on function "api"."create_team"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."update_team"(team uuid, name text, description text, patch jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_team"($1, $2, $3, $4) $$;
revoke execute on function "api"."update_team"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."update_team"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."archive_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_team"($1) $$;
revoke execute on function "api"."archive_team"(uuid) from public, anon;
grant execute on function "api"."archive_team"(uuid) to authenticated, service_role;

create or replace function "api"."restore_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_team"($1) $$;
revoke execute on function "api"."restore_team"(uuid) from public, anon;
grant execute on function "api"."restore_team"(uuid) to authenticated, service_role;

create or replace function "api"."delete_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_team"($1) $$;
revoke execute on function "api"."delete_team"(uuid) from public, anon;
grant execute on function "api"."delete_team"(uuid) to authenticated, service_role;

create or replace function "api"."add_team_member"(team uuid, member uuid default null, employee uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_team_member"($1, $2, $3) $$;
revoke execute on function "api"."add_team_member"(uuid, uuid, uuid) from public, anon;
grant execute on function "api"."add_team_member"(uuid, uuid, uuid) to authenticated, service_role;

create or replace function "api"."remove_team_member"(team uuid, member uuid default null, employee uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_team_member"($1, $2, $3) $$;
revoke execute on function "api"."remove_team_member"(uuid, uuid, uuid) from public, anon;
grant execute on function "api"."remove_team_member"(uuid, uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_teams"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_teams"($1) $$;
revoke execute on function "api"."list_teams"(uuid) from public, anon;
grant execute on function "api"."list_teams"(uuid) to authenticated, service_role;
