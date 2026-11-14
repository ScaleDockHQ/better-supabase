-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:c08f405aa38745eaa4b6037f0345da8a06387b91975aad15facc47012d705e81
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
create or replace function "better_supabase"."purge_team"(team uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

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
