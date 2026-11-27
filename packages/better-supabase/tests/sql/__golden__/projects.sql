-- ==== alone: schema supabase/schemas/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block projects@1 managed
-- @bsb-hash sha256:f57a4dac2def95d73ab08fea853f1ef188f956e6e7b02915fd0956531a5d5f9d
-- Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."project_updates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "author_id" uuid,
  "health" text not null constraint bsb_project_updates_health_check check ("health" in ('on_track', 'at_risk', 'off_track')),
  "body" text not null constraint bsb_project_updates_body_check check (length("body") >= 1 and length("body") <= 20000),
  "scope_count" integer not null default 0,
  "started_count" integer not null default 0,
  "completed_count" integer not null default 0,
  "created_at" timestamptz not null default now()
);
create index project_updates_project_idx on "better_supabase"."project_updates" ("project_id", "created_at" desc);

create table "better_supabase"."initiatives" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_initiatives_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text,
  "status" text not null default 'proposed' constraint bsb_initiatives_status_check check ("status" in ('proposed', 'planned', 'active', 'completed', 'canceled')),
  "priority" smallint not null default 0 constraint bsb_initiatives_priority_check check ("priority" >= 0 and "priority" <= 4),
  "owner_id" uuid,
  "target_on" date,
  "parent_id" uuid references "better_supabase"."initiatives" ("id") on delete set null,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index initiatives_parent_idx on "better_supabase"."initiatives" ("parent_id") where "parent_id" is not null;

create table "better_supabase"."initiative_projects" (
  "initiative_id" uuid not null references "better_supabase"."initiatives" ("id") on delete cascade,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "tenant_id" uuid not null,
  primary key ("initiative_id", "project_id")
);
create index initiative_projects_project_idx on "better_supabase"."initiative_projects" ("project_id");

create or replace function "better_supabase"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row "better_supabase"."project_updates";
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'health must be on_track, at_risk or off_track' using errcode = '22023', hint = 'PROJECT_UPDATE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."projects" p where p."id" = save_project_update.project and p."tenant_id" = save_project_update.tenant) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'PROJECT_NOT_FOUND';
  end if;
  select count(*)::integer,
    count(*) filter (where t."state" = 'started')::integer,
    count(*) filter (where t."state" = 'completed')::integer
  into v_scope, v_started, v_completed
  from "better_supabase"."tasks" t
  where t."project_id" = save_project_update.project;
  insert into "better_supabase"."project_updates" ("tenant_id", "project_id", "author_id", "health", "body", "scope_count", "started_count", "completed_count")
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform "better_supabase"."set_project_health"(save_project_update.project, save_project_update.health);
  null;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."project_updates" x where x."project_id" = page_project_updates.project
$$;
revoke execute on function "better_supabase"."page_project_updates"(uuid) from public, anon;
grant execute on function "better_supabase"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(better_supabase.can('tenant', save_initiative.tenant, initiatives.manage), false)) then
    raise exception 'not allowed to change initiatives' using errcode = '42501', hint = 'INITIATIVE_FORBIDDEN';
  end if;
  if save_initiative.id is null then
    insert into "better_supabase"."initiatives" ("tenant_id", "name", "description", "status", "priority", "owner_id", "target_on", "parent_id", "rank")
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    null;
  else
    update "better_supabase"."initiatives" x set
      "name" = coalesce(save_initiative.attrs ->> 'name', x."name"),
      "description" = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x."description" end,
      "status" = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x."status"),
      "priority" = coalesce((save_initiative.attrs ->> 'priority')::smallint, x."priority"),
      "updated_at" = now()
    where x."id" = save_initiative.id and x."tenant_id" = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent."id" as id, parent."parent_id" as parent
          from "better_supabase"."initiatives" parent
          where parent."id" = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next."id", next."parent_id"
          from "better_supabase"."initiatives" next
          join chain on next."id" = chain.parent
        )
        select 1 from chain where chain.id = x."id"
      ))
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'initiative not found' using errcode = 'P0002', hint = 'INITIATIVE_NOT_FOUND';
    end if;
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u."health" from "better_supabase"."initiative_projects" link
    join "better_supabase"."project_updates" u on u."project_id" = link."project_id"
    where link."initiative_id" = x."id"
    order by u."created_at" desc
    limit 1
  ))
  from "better_supabase"."initiatives" x where x."id" = get_initiative.initiative
$$;
revoke execute on function "better_supabase"."get_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."rank", x."name"), '[]'::jsonb)
  from "better_supabase"."initiatives" x
  where x."tenant_id" = page_initiatives.tenant and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."page_initiatives"(uuid) from public, anon;
grant execute on function "better_supabase"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."initiatives" x set
    "archived_at" = case when archive_initiative.archived then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = archive_initiative.initiative and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_initiative"(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."initiatives" x
  where x."id" = remove_initiative.initiative and x."archived_at" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."link_initiative_project"(initiative uuid, project uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."initiatives" x where x."id" = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into "better_supabase"."initiative_projects" ("initiative_id", "project_id", "tenant_id")
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block-data projects
-- @bsb-hash sha256:5059ed6bb41ff3591e32387c061c43ccd3b3055875d7ff998855b8dc2929ed59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('projects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block projects@1 managed
-- @bsb-hash sha256:4685bc24462a8e3b30971c3a5abec0474de2b2b9f7d40666db4e3f7a12bf73d4
-- Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."project_updates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "author_id" uuid,
  "health" text not null constraint bsb_project_updates_health_check check ("health" in ('on_track', 'at_risk', 'off_track')),
  "body" text not null constraint bsb_project_updates_body_check check (length("body") >= 1 and length("body") <= 20000),
  "scope_count" integer not null default 0,
  "started_count" integer not null default 0,
  "completed_count" integer not null default 0,
  "created_at" timestamptz not null default now()
);
create index project_updates_project_idx on "better_supabase"."project_updates" ("project_id", "created_at" desc);

create table "better_supabase"."initiatives" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_initiatives_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text,
  "status" text not null default 'proposed' constraint bsb_initiatives_status_check check ("status" in ('proposed', 'planned', 'active', 'completed', 'canceled')),
  "priority" smallint not null default 0 constraint bsb_initiatives_priority_check check ("priority" >= 0 and "priority" <= 4),
  "owner_id" uuid,
  "target_on" date,
  "parent_id" uuid references "better_supabase"."initiatives" ("id") on delete set null,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index initiatives_parent_idx on "better_supabase"."initiatives" ("parent_id") where "parent_id" is not null;

create table "better_supabase"."initiative_projects" (
  "initiative_id" uuid not null references "better_supabase"."initiatives" ("id") on delete cascade,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "tenant_id" uuid not null,
  primary key ("initiative_id", "project_id")
);
create index initiative_projects_project_idx on "better_supabase"."initiative_projects" ("project_id");

create or replace function "better_supabase"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row "better_supabase"."project_updates";
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'health must be on_track, at_risk or off_track' using errcode = '22023', hint = 'PROJECT_UPDATE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."projects" p where p."id" = save_project_update.project and p."tenant_id" = save_project_update.tenant) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'PROJECT_NOT_FOUND';
  end if;
  select count(*)::integer,
    count(*) filter (where t."state" = 'started')::integer,
    count(*) filter (where t."state" = 'completed')::integer
  into v_scope, v_started, v_completed
  from "better_supabase"."tasks" t
  where t."project_id" = save_project_update.project;
  insert into "better_supabase"."project_updates" ("tenant_id", "project_id", "author_id", "health", "body", "scope_count", "started_count", "completed_count")
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform "better_supabase"."set_project_health"(save_project_update.project, save_project_update.health);
  perform "better_supabase".emit_event('project_update.created', jsonb_build_object('organizationId', v_row."tenant_id", 'projectId', v_row."project_id", 'updateId', v_row."id", 'subjectType', 'project_update', 'subjectId', v_row."id"::text, 'health', v_row."health", 'actorId', auth.uid(), 'actorKind', null, 'actorName', null), 'updates/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/projects');
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object('type', 'project_update.created', 'tenant', v_row."tenant_id", 'subject_type', 'project_update', 'subject_id', v_row."project_id"::text));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."project_updates" x where x."project_id" = page_project_updates.project
$$;
revoke execute on function "better_supabase"."page_project_updates"(uuid) from public, anon;
grant execute on function "better_supabase"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(better_supabase.can('tenant', save_initiative.tenant, initiatives.manage), false)) then
    raise exception 'not allowed to change initiatives' using errcode = '42501', hint = 'INITIATIVE_FORBIDDEN';
  end if;
  if save_initiative.id is null then
    insert into "better_supabase"."initiatives" ("tenant_id", "name", "description", "status", "priority", "owner_id", "target_on", "parent_id", "rank")
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    perform "better_supabase".emit_event('initiative.created', jsonb_build_object('organizationId', v_row."tenant_id", 'initiativeId', v_row."id", 'subjectType', 'initiative', 'subjectId', v_row."id"::text, 'name', v_row."name", 'actorId', auth.uid(), 'actorKind', null, 'actorName', null), 'initiatives/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/projects');
  else
    update "better_supabase"."initiatives" x set
      "name" = coalesce(save_initiative.attrs ->> 'name', x."name"),
      "description" = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x."description" end,
      "status" = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x."status"),
      "priority" = coalesce((save_initiative.attrs ->> 'priority')::smallint, x."priority"),
      "updated_at" = now()
    where x."id" = save_initiative.id and x."tenant_id" = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent."id" as id, parent."parent_id" as parent
          from "better_supabase"."initiatives" parent
          where parent."id" = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next."id", next."parent_id"
          from "better_supabase"."initiatives" next
          join chain on next."id" = chain.parent
        )
        select 1 from chain where chain.id = x."id"
      ))
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'initiative not found' using errcode = 'P0002', hint = 'INITIATIVE_NOT_FOUND';
    end if;
    perform "better_supabase".emit_event('initiative.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'initiativeId', v_row."id", 'subjectType', 'initiative', 'subjectId', v_row."id"::text, 'name', v_row."name", 'actorId', auth.uid(), 'actorKind', null, 'actorName', null), 'initiatives/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/projects');
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u."health" from "better_supabase"."initiative_projects" link
    join "better_supabase"."project_updates" u on u."project_id" = link."project_id"
    where link."initiative_id" = x."id"
    order by u."created_at" desc
    limit 1
  ))
  from "better_supabase"."initiatives" x where x."id" = get_initiative.initiative
$$;
revoke execute on function "better_supabase"."get_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."rank", x."name"), '[]'::jsonb)
  from "better_supabase"."initiatives" x
  where x."tenant_id" = page_initiatives.tenant and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."page_initiatives"(uuid) from public, anon;
grant execute on function "better_supabase"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."initiatives" x set
    "archived_at" = case when archive_initiative.archived then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = archive_initiative.initiative and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('initiative.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'initiativeId', v_row."id", 'subjectType', 'initiative', 'subjectId', v_row."id"::text, 'name', v_row."name", 'actorId', auth.uid(), 'actorKind', null, 'actorName', null), 'initiatives/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/projects');
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_initiative"(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."initiatives" x
  where x."id" = remove_initiative.initiative and x."archived_at" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('initiative.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'initiativeId', v_row."id", 'subjectType', 'initiative', 'subjectId', v_row."id"::text, 'name', v_row."name", 'actorId', auth.uid(), 'actorKind', null, 'actorName', null), 'initiatives/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/projects');
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."link_initiative_project"(initiative uuid, project uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."initiatives" x where x."id" = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into "better_supabase"."initiative_projects" ("initiative_id", "project_id", "tenant_id")
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.project_updates deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"project_update","event_prefix":"project_update"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.initiatives deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"initiative","event_prefix":"initiative","archive_column":"archived_at"}');

-- Realtime for the module's entities (subject.realtime)
create trigger bsb_realtime_insert after insert on "better_supabase"."project_updates" referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_update after update on "better_supabase"."project_updates" referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_delete after delete on "better_supabase"."project_updates" referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_insert after insert on "better_supabase"."initiatives" referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_update after update on "better_supabase"."initiatives" referencing old table as old_rows new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');
create trigger bsb_realtime_delete after delete on "better_supabase"."initiatives" referencing old table as old_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block-data projects
-- @bsb-hash sha256:5059ed6bb41ff3591e32387c061c43ccd3b3055875d7ff998855b8dc2929ed59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('projects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block projects@1 managed
-- @bsb-hash sha256:dad8e9eb1b8ea3fa335ae6e1d264fbae59d69f828c74eb2100a0e090b86176be
-- Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges for role postgres in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on functions from public, anon, authenticated;
create table "app_private"."project_updates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "author_id" uuid,
  "health" text not null constraint bsb_project_updates_health_check check ("health" in ('on_track', 'at_risk', 'off_track')),
  "body" text not null constraint bsb_project_updates_body_check check (length("body") >= 1 and length("body") <= 20000),
  "scope_count" integer not null default 0,
  "started_count" integer not null default 0,
  "completed_count" integer not null default 0,
  "created_at" timestamptz not null default now()
);
create index project_updates_project_idx on "app_private"."project_updates" ("project_id", "created_at" desc);

create table "app_private"."initiatives" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_initiatives_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text,
  "status" text not null default 'proposed' constraint bsb_initiatives_status_check check ("status" in ('proposed', 'planned', 'active', 'completed', 'canceled')),
  "priority" smallint not null default 0 constraint bsb_initiatives_priority_check check ("priority" >= 0 and "priority" <= 4),
  "owner_id" uuid,
  "target_on" date,
  "parent_id" uuid references "app_private"."initiatives" ("id") on delete set null,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index initiatives_parent_idx on "app_private"."initiatives" ("parent_id") where "parent_id" is not null;

create table "app_private"."initiative_projects" (
  "initiative_id" uuid not null references "app_private"."initiatives" ("id") on delete cascade,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "tenant_id" uuid not null,
  primary key ("initiative_id", "project_id")
);
create index initiative_projects_project_idx on "app_private"."initiative_projects" ("project_id");

create or replace function "app_private"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row "app_private"."project_updates";
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'health must be on_track, at_risk or off_track' using errcode = '22023', hint = 'PROJECT_UPDATE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."projects" p where p."id" = save_project_update.project and p."tenant_id" = save_project_update.tenant) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'PROJECT_NOT_FOUND';
  end if;
  select count(*)::integer,
    count(*) filter (where t."state" = 'started')::integer,
    count(*) filter (where t."state" = 'completed')::integer
  into v_scope, v_started, v_completed
  from "better_supabase"."tasks" t
  where t."project_id" = save_project_update.project;
  insert into "app_private"."project_updates" ("tenant_id", "project_id", "author_id", "health", "body", "scope_count", "started_count", "completed_count")
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform "better_supabase"."set_project_health"(save_project_update.project, save_project_update.health);
  null;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "app_private"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc), '[]'::jsonb)
  from "app_private"."project_updates" x where x."project_id" = page_project_updates.project
$$;
revoke execute on function "app_private"."page_project_updates"(uuid) from public, anon;
grant execute on function "app_private"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "app_private"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(better_supabase.can('tenant', save_initiative.tenant, initiatives.manage), false)) then
    raise exception 'not allowed to change initiatives' using errcode = '42501', hint = 'INITIATIVE_FORBIDDEN';
  end if;
  if save_initiative.id is null then
    insert into "app_private"."initiatives" ("tenant_id", "name", "description", "status", "priority", "owner_id", "target_on", "parent_id", "rank")
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    null;
  else
    update "app_private"."initiatives" x set
      "name" = coalesce(save_initiative.attrs ->> 'name', x."name"),
      "description" = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x."description" end,
      "status" = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x."status"),
      "priority" = coalesce((save_initiative.attrs ->> 'priority')::smallint, x."priority"),
      "updated_at" = now()
    where x."id" = save_initiative.id and x."tenant_id" = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent."id" as id, parent."parent_id" as parent
          from "app_private"."initiatives" parent
          where parent."id" = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next."id", next."parent_id"
          from "app_private"."initiatives" next
          join chain on next."id" = chain.parent
        )
        select 1 from chain where chain.id = x."id"
      ))
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'initiative not found' using errcode = 'P0002', hint = 'INITIATIVE_NOT_FOUND';
    end if;
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u."health" from "app_private"."initiative_projects" link
    join "app_private"."project_updates" u on u."project_id" = link."project_id"
    where link."initiative_id" = x."id"
    order by u."created_at" desc
    limit 1
  ))
  from "app_private"."initiatives" x where x."id" = get_initiative.initiative
$$;
revoke execute on function "app_private"."get_initiative"(uuid) from public, anon;
grant execute on function "app_private"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "app_private"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."rank", x."name"), '[]'::jsonb)
  from "app_private"."initiatives" x
  where x."tenant_id" = page_initiatives.tenant and x."archived_at" is null
$$;
revoke execute on function "app_private"."page_initiatives"(uuid) from public, anon;
grant execute on function "app_private"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "app_private"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."initiatives" x set
    "archived_at" = case when archive_initiative.archived then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = archive_initiative.initiative and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "app_private"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."remove_initiative"(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."initiatives" x
  where x."id" = remove_initiative.initiative and x."archived_at" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."remove_initiative"(uuid) from public, anon;
grant execute on function "app_private"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "app_private"."link_initiative_project"(initiative uuid, project uuid)
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
  select x."tenant_id" into v_tenant from "app_private"."initiatives" x where x."id" = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into "app_private"."initiative_projects" ("initiative_id", "project_id", "tenant_id")
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "app_private"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "app_private"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block-data projects
-- @bsb-hash sha256:5059ed6bb41ff3591e32387c061c43ccd3b3055875d7ff998855b8dc2929ed59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('projects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block projects@1 managed
-- @bsb-hash sha256:60ae7b4cadbe61c1102700b4b04ff7cd86bc29c613e0b232f998dadef67ddd54
-- Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."project_updates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "author_id" uuid,
  "health" text not null constraint bsb_project_updates_health_check check ("health" in ('on_track', 'at_risk', 'off_track')),
  "body" text not null constraint bsb_project_updates_body_check check (length("body") >= 1 and length("body") <= 20000),
  "scope_count" integer not null default 0,
  "started_count" integer not null default 0,
  "completed_count" integer not null default 0,
  "created_at" timestamptz not null default now()
);
create index project_updates_project_idx on "better_supabase"."project_updates" ("project_id", "created_at" desc);

create table "better_supabase"."initiatives" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_initiatives_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text,
  "status" text not null default 'proposed' constraint bsb_initiatives_status_check check ("status" in ('proposed', 'planned', 'active', 'completed', 'canceled')),
  "priority" smallint not null default 0 constraint bsb_initiatives_priority_check check ("priority" >= 0 and "priority" <= 4),
  "owner_id" uuid,
  "target_on" date,
  "parent_id" uuid references "better_supabase"."initiatives" ("id") on delete set null,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index initiatives_parent_idx on "better_supabase"."initiatives" ("parent_id") where "parent_id" is not null;

create table "better_supabase"."initiative_projects" (
  "initiative_id" uuid not null references "better_supabase"."initiatives" ("id") on delete cascade,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "tenant_id" uuid not null,
  primary key ("initiative_id", "project_id")
);
create index initiative_projects_project_idx on "better_supabase"."initiative_projects" ("project_id");

create or replace function "better_supabase"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row "better_supabase"."project_updates";
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'health must be on_track, at_risk or off_track' using errcode = '22023', hint = 'PROJECT_UPDATE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."projects" p where p."id" = save_project_update.project and p."tenant_id" = save_project_update.tenant) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'PROJECT_NOT_FOUND';
  end if;
  select count(*)::integer,
    count(*) filter (where t."state" = 'started')::integer,
    count(*) filter (where t."state" = 'completed')::integer
  into v_scope, v_started, v_completed
  from "better_supabase"."tasks" t
  where t."project_id" = save_project_update.project;
  insert into "better_supabase"."project_updates" ("tenant_id", "project_id", "author_id", "health", "body", "scope_count", "started_count", "completed_count")
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform "better_supabase"."set_project_health"(save_project_update.project, save_project_update.health);
  null;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."project_updates" x where x."project_id" = page_project_updates.project
$$;
revoke execute on function "better_supabase"."page_project_updates"(uuid) from public, anon;
grant execute on function "better_supabase"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(better_supabase.can('tenant', save_initiative.tenant, initiatives.manage), false)) then
    raise exception 'not allowed to change initiatives' using errcode = '42501', hint = 'INITIATIVE_FORBIDDEN';
  end if;
  if save_initiative.id is null then
    insert into "better_supabase"."initiatives" ("tenant_id", "name", "description", "status", "priority", "owner_id", "target_on", "parent_id", "rank")
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    null;
  else
    update "better_supabase"."initiatives" x set
      "name" = coalesce(save_initiative.attrs ->> 'name', x."name"),
      "description" = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x."description" end,
      "status" = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x."status"),
      "priority" = coalesce((save_initiative.attrs ->> 'priority')::smallint, x."priority"),
      "updated_at" = now()
    where x."id" = save_initiative.id and x."tenant_id" = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent."id" as id, parent."parent_id" as parent
          from "better_supabase"."initiatives" parent
          where parent."id" = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next."id", next."parent_id"
          from "better_supabase"."initiatives" next
          join chain on next."id" = chain.parent
        )
        select 1 from chain where chain.id = x."id"
      ))
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'initiative not found' using errcode = 'P0002', hint = 'INITIATIVE_NOT_FOUND';
    end if;
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u."health" from "better_supabase"."initiative_projects" link
    join "better_supabase"."project_updates" u on u."project_id" = link."project_id"
    where link."initiative_id" = x."id"
    order by u."created_at" desc
    limit 1
  ))
  from "better_supabase"."initiatives" x where x."id" = get_initiative.initiative
$$;
revoke execute on function "better_supabase"."get_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."rank", x."name"), '[]'::jsonb)
  from "better_supabase"."initiatives" x
  where x."tenant_id" = page_initiatives.tenant and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."page_initiatives"(uuid) from public, anon;
grant execute on function "better_supabase"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."initiatives" x set
    "archived_at" = case when archive_initiative.archived then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = archive_initiative.initiative and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_initiative"(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."initiatives" x
  where x."id" = remove_initiative.initiative and x."archived_at" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."link_initiative_project"(initiative uuid, project uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."initiatives" x where x."id" = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into "better_supabase"."initiative_projects" ("initiative_id", "project_id", "tenant_id")
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- blocks.projects.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_project_update"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "api"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "api"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_project_updates"($1) $$;
revoke execute on function "api"."page_project_updates"(uuid) from public, anon;
grant execute on function "api"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "api"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_initiative"($1, $2, $3) $$;
revoke execute on function "api"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_initiative"($1) $$;
revoke execute on function "api"."get_initiative"(uuid) from public, anon;
grant execute on function "api"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "api"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_initiatives"($1) $$;
revoke execute on function "api"."page_initiatives"(uuid) from public, anon;
grant execute on function "api"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "api"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_initiative"($1, $2) $$;
revoke execute on function "api"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."remove_initiative"(initiative uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_initiative"($1) $$;
revoke execute on function "api"."remove_initiative"(uuid) from public, anon;
grant execute on function "api"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "api"."link_initiative_project"(initiative uuid, project uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_initiative_project"($1, $2) $$;
revoke execute on function "api"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "api"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block-data projects
-- @bsb-hash sha256:5059ed6bb41ff3591e32387c061c43ccd3b3055875d7ff998855b8dc2929ed59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('projects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block projects@1 managed
-- @bsb-hash sha256:f583e718cce3dc0924e4c701a27ed62e620fe76d9cc2d2afabb410135f569c2d
-- Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.project_updates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."project_updates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."project_updates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."project_updates" add column if not exists "project_id" uuid references "better_supabase"."projects" ("id") on delete cascade;
alter table "better_supabase"."project_updates" add column if not exists "author_id" uuid;
alter table "better_supabase"."project_updates" add column if not exists "health" text constraint bsb_project_updates_health_check check ("health" in ('on_track', 'at_risk', 'off_track'));
alter table "better_supabase"."project_updates" add column if not exists "body" text constraint bsb_project_updates_body_check check (length("body") >= 1 and length("body") <= 20000);
alter table "better_supabase"."project_updates" add column if not exists "scope_count" integer not null default 0;
alter table "better_supabase"."project_updates" add column if not exists "started_count" integer not null default 0;
alter table "better_supabase"."project_updates" add column if not exists "completed_count" integer not null default 0;
alter table "better_supabase"."project_updates" add column if not exists "created_at" timestamptz not null default now();
create index if not exists project_updates_project_idx on "better_supabase"."project_updates" ("project_id", "created_at" desc);

-- better_supabase.initiatives is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."initiatives" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."initiatives" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."initiatives" add column if not exists "name" text constraint bsb_initiatives_name_check check (length("name") >= 1 and length("name") <= 200);
alter table "better_supabase"."initiatives" add column if not exists "description" text;
alter table "better_supabase"."initiatives" add column if not exists "status" text not null default 'proposed' constraint bsb_initiatives_status_check check ("status" in ('proposed', 'planned', 'active', 'completed', 'canceled'));
alter table "better_supabase"."initiatives" add column if not exists "priority" smallint not null default 0 constraint bsb_initiatives_priority_check check ("priority" >= 0 and "priority" <= 4);
alter table "better_supabase"."initiatives" add column if not exists "owner_id" uuid;
alter table "better_supabase"."initiatives" add column if not exists "target_on" date;
alter table "better_supabase"."initiatives" add column if not exists "parent_id" uuid references "better_supabase"."initiatives" ("id") on delete set null;
alter table "better_supabase"."initiatives" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."initiatives" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."initiatives" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."initiatives" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists initiatives_parent_idx on "better_supabase"."initiatives" ("parent_id") where "parent_id" is not null;

-- better_supabase.initiative_projects is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."initiative_projects" add column if not exists "initiative_id" uuid references "better_supabase"."initiatives" ("id") on delete cascade;
alter table "better_supabase"."initiative_projects" add column if not exists "project_id" uuid references "better_supabase"."projects" ("id") on delete cascade;
alter table "better_supabase"."initiative_projects" add column if not exists "tenant_id" uuid;
create index if not exists initiative_projects_project_idx on "better_supabase"."initiative_projects" ("project_id");

create or replace function "better_supabase"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row "better_supabase"."project_updates";
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'health must be on_track, at_risk or off_track' using errcode = '22023', hint = 'PROJECT_UPDATE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."projects" p where p."id" = save_project_update.project and p."tenant_id" = save_project_update.tenant) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'PROJECT_NOT_FOUND';
  end if;
  select count(*)::integer,
    count(*) filter (where t."state" = 'started')::integer,
    count(*) filter (where t."state" = 'completed')::integer
  into v_scope, v_started, v_completed
  from "better_supabase"."tasks" t
  where t."project_id" = save_project_update.project;
  insert into "better_supabase"."project_updates" ("tenant_id", "project_id", "author_id", "health", "body", "scope_count", "started_count", "completed_count")
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform "better_supabase"."set_project_health"(save_project_update.project, save_project_update.health);
  null;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."project_updates" x where x."project_id" = page_project_updates.project
$$;
revoke execute on function "better_supabase"."page_project_updates"(uuid) from public, anon;
grant execute on function "better_supabase"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(better_supabase.can('tenant', save_initiative.tenant, initiatives.manage), false)) then
    raise exception 'not allowed to change initiatives' using errcode = '42501', hint = 'INITIATIVE_FORBIDDEN';
  end if;
  if save_initiative.id is null then
    insert into "better_supabase"."initiatives" ("tenant_id", "name", "description", "status", "priority", "owner_id", "target_on", "parent_id", "rank")
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    null;
  else
    update "better_supabase"."initiatives" x set
      "name" = coalesce(save_initiative.attrs ->> 'name', x."name"),
      "description" = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x."description" end,
      "status" = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x."status"),
      "priority" = coalesce((save_initiative.attrs ->> 'priority')::smallint, x."priority"),
      "updated_at" = now()
    where x."id" = save_initiative.id and x."tenant_id" = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent."id" as id, parent."parent_id" as parent
          from "better_supabase"."initiatives" parent
          where parent."id" = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next."id", next."parent_id"
          from "better_supabase"."initiatives" next
          join chain on next."id" = chain.parent
        )
        select 1 from chain where chain.id = x."id"
      ))
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'initiative not found' using errcode = 'P0002', hint = 'INITIATIVE_NOT_FOUND';
    end if;
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u."health" from "better_supabase"."initiative_projects" link
    join "better_supabase"."project_updates" u on u."project_id" = link."project_id"
    where link."initiative_id" = x."id"
    order by u."created_at" desc
    limit 1
  ))
  from "better_supabase"."initiatives" x where x."id" = get_initiative.initiative
$$;
revoke execute on function "better_supabase"."get_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."rank", x."name"), '[]'::jsonb)
  from "better_supabase"."initiatives" x
  where x."tenant_id" = page_initiatives.tenant and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."page_initiatives"(uuid) from public, anon;
grant execute on function "better_supabase"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."initiatives" x set
    "archived_at" = case when archive_initiative.archived then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = archive_initiative.initiative and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_initiative"(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."initiatives" x
  where x."id" = remove_initiative.initiative and x."archived_at" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."link_initiative_project"(initiative uuid, project uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."initiatives" x where x."id" = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into "better_supabase"."initiative_projects" ("initiative_id", "project_id", "tenant_id")
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block-data projects
-- @bsb-hash sha256:5059ed6bb41ff3591e32387c061c43ccd3b3055875d7ff998855b8dc2929ed59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('projects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block projects@1 managed
-- @bsb-hash sha256:9eed3403fd874cbfbfe1d85fac107d822e858b391a8829053a297ae54df3c3a4
-- Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."project_updates" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "author_id" uuid,
  "health" text not null constraint bsb_project_updates_health_check check ("health" in ('on_track', 'at_risk', 'off_track')),
  "body" text not null constraint bsb_project_updates_body_check check (length("body") >= 1 and length("body") <= 20000),
  "scope_count" integer not null default 0,
  "started_count" integer not null default 0,
  "completed_count" integer not null default 0,
  "created_at" timestamptz not null default now()
);
create index project_updates_project_idx on "better_supabase"."project_updates" ("project_id", "created_at" desc);

create table "better_supabase"."initiatives" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null constraint bsb_initiatives_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text,
  "status" text not null default 'proposed' constraint bsb_initiatives_status_check check ("status" in ('proposed', 'planned', 'active', 'completed', 'canceled')),
  "priority" smallint not null default 0 constraint bsb_initiatives_priority_check check ("priority" >= 0 and "priority" <= 4),
  "owner_id" uuid,
  "target_on" date,
  "parent_id" uuid references "better_supabase"."initiatives" ("id") on delete set null,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index initiatives_parent_idx on "better_supabase"."initiatives" ("parent_id") where "parent_id" is not null;

create table "better_supabase"."initiative_projects" (
  "initiative_id" uuid not null references "better_supabase"."initiatives" ("id") on delete cascade,
  "project_id" uuid not null references "better_supabase"."projects" ("id") on delete cascade,
  "org_id" uuid not null,
  primary key ("initiative_id", "project_id")
);
create index initiative_projects_project_idx on "better_supabase"."initiative_projects" ("project_id");

create or replace function "better_supabase"."save_project_update"(tenant uuid, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row "better_supabase"."project_updates";
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    raise exception 'health must be on_track, at_risk or off_track' using errcode = '22023', hint = 'PROJECT_UPDATE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."projects" p where p."id" = save_project_update.project and p."org_id" = save_project_update.tenant) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'PROJECT_NOT_FOUND';
  end if;
  select count(*)::integer,
    count(*) filter (where t."state" = 'started')::integer,
    count(*) filter (where t."state" = 'completed')::integer
  into v_scope, v_started, v_completed
  from "better_supabase"."tasks" t
  where t."project_id" = save_project_update.project;
  insert into "better_supabase"."project_updates" ("org_id", "project_id", "author_id", "health", "body", "scope_count", "started_count", "completed_count")
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform "better_supabase"."set_project_health"(save_project_update.project, save_project_update.health);
  null;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_project_update"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."page_project_updates"(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."project_updates" x where x."project_id" = page_project_updates.project
$$;
revoke execute on function "better_supabase"."page_project_updates"(uuid) from public, anon;
grant execute on function "better_supabase"."page_project_updates"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_initiative"(tenant uuid, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(better_supabase.can('tenant', save_initiative.tenant, initiatives.manage), false)) then
    raise exception 'not allowed to change initiatives' using errcode = '42501', hint = 'INITIATIVE_FORBIDDEN';
  end if;
  if save_initiative.id is null then
    insert into "better_supabase"."initiatives" ("org_id", "name", "description", "status", "priority", "owner_id", "target_on", "parent_id", "rank")
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    null;
  else
    update "better_supabase"."initiatives" x set
      "name" = coalesce(save_initiative.attrs ->> 'name', x."name"),
      "description" = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x."description" end,
      "status" = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x."status"),
      "priority" = coalesce((save_initiative.attrs ->> 'priority')::smallint, x."priority"),
      "updated_at" = now()
    where x."id" = save_initiative.id and x."org_id" = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent."id" as id, parent."parent_id" as parent
          from "better_supabase"."initiatives" parent
          where parent."id" = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next."id", next."parent_id"
          from "better_supabase"."initiatives" next
          join chain on next."id" = chain.parent
        )
        select 1 from chain where chain.id = x."id"
      ))
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'initiative not found' using errcode = 'P0002', hint = 'INITIATIVE_NOT_FOUND';
    end if;
    null;
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_initiative"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_initiative"(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u."health" from "better_supabase"."initiative_projects" link
    join "better_supabase"."project_updates" u on u."project_id" = link."project_id"
    where link."initiative_id" = x."id"
    order by u."created_at" desc
    limit 1
  ))
  from "better_supabase"."initiatives" x where x."id" = get_initiative.initiative
$$;
revoke execute on function "better_supabase"."get_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."get_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."page_initiatives"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."rank", x."name"), '[]'::jsonb)
  from "better_supabase"."initiatives" x
  where x."org_id" = page_initiatives.tenant and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."page_initiatives"(uuid) from public, anon;
grant execute on function "better_supabase"."page_initiatives"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_initiative"(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."initiatives" x set
    "archived_at" = case when archive_initiative.archived then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = archive_initiative.initiative and coalesce(better_supabase.can('tenant', x."org_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_initiative"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_initiative"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_initiative"(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."initiatives";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."initiatives" x
  where x."id" = remove_initiative.initiative and x."archived_at" is not null and coalesce(better_supabase.can('tenant', x."org_id", initiatives.manage), false)
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_initiative"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_initiative"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."link_initiative_project"(initiative uuid, project uuid)
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
  select x."org_id" into v_tenant from "better_supabase"."initiatives" x where x."id" = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into "better_supabase"."initiative_projects" ("initiative_id", "project_id", "org_id")
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."link_initiative_project"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."link_initiative_project"(uuid, uuid) to authenticated, service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_185_projects.sql
-- better-supabase module: projects
-- @bsb-block-data projects
-- @bsb-hash sha256:5059ed6bb41ff3591e32387c061c43ccd3b3055875d7ff998855b8dc2929ed59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('projects', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
