-- ==== schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@2 managed
-- @bsb-hash sha256:cbfa485175ddff519c696828b553b11caef429a6cbeff055b5b03e6873d79d28
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.column_default(relation text, name text, target anyelement)
returns anyelement
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
  v_default text;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = pg_catalog.to_regclass(column_default.relation) and a.attname = column_default.name and not a.attisdropped;
  if v_default is not null then
    execute 'select ' || v_default into result;
  end if;
  return result;
end;
$$;
revoke execute on function better_supabase.column_default(text, text, anyelement) from public, anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."teams";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."teams";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."teams";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."teams";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."teams";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."team_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."team_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."team_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."team_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."team_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table if not exists "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "slug" text not null check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
alter table "better_supabase"."teams" add column if not exists "app_note" text;
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
drop policy if exists teams_read on "better_supabase"."teams";
create policy teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table if not exists "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index if not exists team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index if not exists team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
drop policy if exists team_members_read on "better_supabase"."team_members";
create policy team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members" drop constraint if exists team_members_membership_fkey;
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "better_supabase"."memberships" ("organization_id", "user_id")
  on delete cascade;


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

-- fields: the extra columns (blocks.teams.options.extraColumns) to set.
drop function if exists "better_supabase"."create_team"(uuid, text, text);
drop function if exists "better_supabase"."create_team"(uuid, text, text, text);
drop function if exists "better_supabase"."create_team"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
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
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by", "app_note")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid(), case when create_team.fields ? 'app_note' then (jsonb_populate_record(null::"better_supabase"."teams", jsonb_build_object('app_note', create_team.fields -> 'app_note')))."app_note" else better_supabase.column_default('"better_supabase"."teams"', 'app_note', (null::"better_supabase"."teams")."app_note") end)
  returning "id" into v_id;
  update "better_supabase"."teams" x set "app_note" = case when create_team.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."teams", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(create_team.fields) e where e.key in ('app_note'))) r
  where x."id" = v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status", 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."teams" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text, jsonb) to authenticated, service_role;

drop function if exists "better_supabase"."update_team"(uuid, text, text);
create or replace function "better_supabase"."update_team"(team uuid, name text, description text, fields jsonb default null)
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
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  update "better_supabase"."teams" x set "app_note" = case when update_team.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."teams", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(update_team.fields) e where e.key in ('app_note'))) r
  where x."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status", 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."teams" x where x."id" = update_team.team);
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
  null;
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
  null;
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
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
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
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
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
    'description', t."description",
    'status', t."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb), 'fields', jsonb_build_object('app_note', t."app_note")
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
drop policy if exists bsb_tenant_scope on "better_supabase"."teams";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."teams";
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."teams";
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."teams";
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."teams";
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."team_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."team_members";
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."team_members";
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."team_members";
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."team_members";
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:73dfb8a9526ca418c3217dfe9e93bcf5b07006c37b0a318922295a314a8ee6c9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
