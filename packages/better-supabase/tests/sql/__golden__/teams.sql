-- ==== alone: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:28479452c009da3cdbf89f37cac07373d87ac012b32684989ad14980c953441e
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
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
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

-- fields: the extra columns (columns your schema files add) to set.

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
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
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
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
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
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:26df8defd85465c0b510765d20c40b48b71650abb045f3085e33f12a6903d30f
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
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
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
  references "better_supabase"."memberships" ("organization_id", "user_id")
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
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
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
  perform "better_supabase".emit_event('team_member.added', jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', add_team_member.member), 'teams/' || (add_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
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
  perform "better_supabase".emit_event('team_member.deleted', jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', remove_team_member.member), 'teams/' || (remove_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.deleted',
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
    'description', t."description",
    'status', t."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
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
create constraint trigger bsb_audit after insert or update or delete on better_supabase.teams deferrable initially deferred for each row execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"team","event_prefix":"team"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:f2b972cd9a62f98eab8d474b954b22e07064a8d67af4ddcf21981708368303c2
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "app_private"."teams" (
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
alter table "app_private"."teams" enable row level security;
revoke all on "app_private"."teams" from public, anon, authenticated;
grant select on "app_private"."teams" to authenticated;
grant all on "app_private"."teams" to service_role;
create policy bsb_teams_read on "app_private"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "app_private"."team_members" (
  "team_id" uuid not null references "app_private"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index team_members_user_idx on "app_private"."team_members" ("user_id");
create index team_members_membership_idx on "app_private"."team_members" ("tenant_id", "user_id");
alter table "app_private"."team_members" enable row level security;
revoke all on "app_private"."team_members" from public, anon, authenticated;
grant select on "app_private"."team_members" to authenticated;
grant all on "app_private"."team_members" to service_role;
create policy bsb_team_members_read on "app_private"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "app_private"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "better_supabase"."memberships" ("organization_id", "user_id")
  on delete cascade;


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "app_private"."team_ids_of"(member uuid)
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
  return query select "team_id" from "app_private"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "app_private"."team_ids_of"(uuid) from public, anon;
grant execute on function "app_private"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "app_private"."create_team"(tenant uuid, name text, description text)
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
  insert into "app_private"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
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
revoke execute on function "app_private"."create_team"(uuid, text, text) from public, anon;
grant execute on function "app_private"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "app_private"."update_team"(team uuid, name text, description text)
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
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "app_private"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "app_private"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "app_private"."update_team"(uuid, text, text) from public, anon;
grant execute on function "app_private"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."archive_team"(team uuid)
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
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "app_private"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_team"(uuid) from public, anon;
grant execute on function "app_private"."archive_team"(uuid) to authenticated, service_role;

create or replace function "app_private"."delete_team"(team uuid)
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
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = delete_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "app_private"."teams" where "id" = delete_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_team"(uuid) from public, anon;
grant execute on function "app_private"."delete_team"(uuid) to authenticated, service_role;

create or replace function "app_private"."add_team_member"(team uuid, member uuid)
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
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = add_team_member.team;
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
  insert into "app_private"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "app_private"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "app_private"."remove_team_member"(team uuid, member uuid)
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
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "app_private"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
end;
$$;
revoke execute on function "app_private"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "app_private"."remove_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "app_private"."list_teams"(tenant uuid)
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
      from "app_private"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb)
  ) order by t."name"), '[]'::jsonb)
  from "app_private"."teams" t
  where t."tenant_id" = list_teams.tenant
    and (
      auth.role() = 'service_role'
      or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)
    )
$$;
revoke execute on function "app_private"."list_teams"(uuid) from public, anon;
grant execute on function "app_private"."list_teams"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:37d14375b3ffa5ff5f0f6129d99286b1c9cd7e756382aecca4638cee9f7502a7
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
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
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

-- fields: the extra columns (columns your schema files add) to set.

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
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
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
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
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
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
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

create or replace function "api"."create_team"(tenant uuid, name text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_team"($1, $2, $3) $$;
revoke execute on function "api"."create_team"(uuid, text, text) from public, anon;
grant execute on function "api"."create_team"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."update_team"(team uuid, name text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_team"($1, $2, $3) $$;
revoke execute on function "api"."update_team"(uuid, text, text) from public, anon;
grant execute on function "api"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."archive_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_team"($1) $$;
revoke execute on function "api"."archive_team"(uuid) from public, anon;
grant execute on function "api"."archive_team"(uuid) to authenticated, service_role;

create or replace function "api"."delete_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_team"($1) $$;
revoke execute on function "api"."delete_team"(uuid) from public, anon;
grant execute on function "api"."delete_team"(uuid) to authenticated, service_role;

create or replace function "api"."add_team_member"(team uuid, member uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_team_member"($1, $2) $$;
revoke execute on function "api"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "api"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."remove_team_member"(team uuid, member uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_team_member"($1, $2) $$;
revoke execute on function "api"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "api"."remove_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_teams"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_teams"($1) $$;
revoke execute on function "api"."list_teams"(uuid) from public, anon;
grant execute on function "api"."list_teams"(uuid) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:e1815e48e85ef2b0ed40fd89ee7c2b12f5661fd2dd989d4880daa2d7a12069cf
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
-- better_supabase.teams is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."teams" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."teams" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."teams" add column if not exists "name" text constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200);
alter table "better_supabase"."teams" add column if not exists "slug" text constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');
alter table "better_supabase"."teams" add column if not exists "description" text;
alter table "better_supabase"."teams" add column if not exists "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived'));
alter table "better_supabase"."teams" add column if not exists "created_by" uuid;
alter table "better_supabase"."teams" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."teams" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."teams" enable row level security;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_select on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

-- better_supabase.team_members is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."team_members" add column if not exists "team_id" uuid references "better_supabase"."teams" ("id") on delete cascade;
alter table "better_supabase"."team_members" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."team_members" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."team_members" add column if not exists "created_at" timestamptz not null default now();
create index if not exists team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index if not exists team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_select on "better_supabase"."team_members"
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
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

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
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
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
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
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
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:c6ed9a38417fa65ceac09725490d60c47093b407c4c2754afd959b4ddec41801
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "slug")
);
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "org_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index team_members_membership_idx on "better_supabase"."team_members" ("org_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("org_id", "user_id")
  references "better_supabase"."memberships" ("org_id", "user_id")
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

-- fields: the extra columns (columns your schema files add) to set.

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
  insert into "better_supabase"."teams" ("org_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
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
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
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
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
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
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
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
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = delete_team.team;
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
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "org_id")
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
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
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
    ), '[]'::jsonb)
  ) order by t."name"), '[]'::jsonb)
  from "better_supabase"."teams" t
  where t."org_id" = list_teams.tenant
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
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
