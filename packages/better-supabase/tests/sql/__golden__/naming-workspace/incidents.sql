-- ==== schema supabase/schemas/900_better_supabase_127_incidents.sql
-- better-supabase module: incidents
-- @bsb-block incidents@1 managed
-- Incidents with a severity, a status timeline of updates, the components they affect and a postmortem, plus a public status page: component status, public incident updates and uptime history, readable anonymously through one function that returns only the fields marked public.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Incidents: severity, a status timeline, affected components, postmortems,
-- and a public status page read through one narrow function.

-- The services a status page reports on. status follows the worst impact of
-- the open incidents on the component; nothing else writes it.
create table if not exists "better_supabase"."status_components" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "group_name" text check ("group_name" is null or length("group_name") <= 100),
  -- Whether the component shows on the public status page.
  "public" boolean not null default true,
  "status" text not null default 'operational' check ("status" in ('operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage')),
  "position" integer not null default 0,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "status_components_tenant_idx" on "better_supabase"."status_components" ("tenant_id", "position");
alter table "better_supabase"."status_components" enable row level security;
revoke all on "better_supabase"."status_components" from anon, authenticated;
grant select on "better_supabase"."status_components" to authenticated;
grant all on "better_supabase"."status_components" to service_role;
drop policy if exists "status_components_read" on "better_supabase"."status_components";
create policy "status_components_read" on "better_supabase"."status_components" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

-- One row per status a component held, for the uptime history.
create table if not exists "better_supabase"."status_component_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "component_id" uuid not null,
  "status" text not null check ("status" in ('operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage')),
  "started_at" timestamptz not null default now(),
  "ended_at" timestamptz,
  check ("ended_at" is null or "ended_at" >= "started_at"),
  foreign key ("tenant_id", "component_id") references "better_supabase"."status_components" ("tenant_id", "id") on delete cascade
);
create index if not exists "status_component_history_component_idx" on "better_supabase"."status_component_history" ("tenant_id", "component_id", "started_at");
create unique index if not exists "status_component_history_open_idx" on "better_supabase"."status_component_history" ("component_id") where "ended_at" is null;
alter table "better_supabase"."status_component_history" enable row level security;
revoke all on "better_supabase"."status_component_history" from anon, authenticated;
grant select on "better_supabase"."status_component_history" to authenticated;
grant all on "better_supabase"."status_component_history" to service_role;
drop policy if exists "status_component_history_read" on "better_supabase"."status_component_history";
create policy "status_component_history_read" on "better_supabase"."status_component_history" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

create table if not exists "better_supabase"."incidents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  -- Internal detail; the public status page never shows it.
  "description" text check ("description" is null or length("description") <= 10000),
  "severity" text not null default 'sev3' check ("severity" in ('sev1', 'sev2', 'sev3', 'sev4')),
  "status" text not null default 'investigating' check ("status" in ('investigating', 'identified', 'monitoring', 'resolved')),
  -- Whether the incident, its public updates and its published postmortem
  -- summary show on the public status page.
  "public" boolean not null default false,
  "commander_id" uuid,
  "started_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("status" = 'resolved') = ("resolved_at" is not null)),
  unique ("tenant_id", "id")
);
create index if not exists "incidents_tenant_idx" on "better_supabase"."incidents" ("tenant_id", "started_at" desc);
create index if not exists "incidents_open_idx" on "better_supabase"."incidents" ("tenant_id") where "status" <> 'resolved';
create index if not exists "incidents_commander_idx" on "better_supabase"."incidents" ("tenant_id", "commander_id") where "commander_id" is not null;
alter table "better_supabase"."incidents" enable row level security;
revoke all on "better_supabase"."incidents" from anon, authenticated;
grant select on "better_supabase"."incidents" to authenticated;
grant all on "better_supabase"."incidents" to service_role;
drop policy if exists "incidents_read" on "better_supabase"."incidents";
create policy "incidents_read" on "better_supabase"."incidents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

-- The status timeline: each update sets the incident's status.
create table if not exists "better_supabase"."incident_updates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "incident_id" uuid not null,
  "status" text not null check ("status" in ('investigating', 'identified', 'monitoring', 'resolved')),
  "body" text not null check (length("body") between 1 and 10000),
  "public" boolean not null default false,
  "author_id" uuid,
  -- clock_timestamp keeps the timeline in order when one transaction posts
  -- several updates.
  "created_at" timestamptz not null default clock_timestamp(),
  foreign key ("tenant_id", "incident_id") references "better_supabase"."incidents" ("tenant_id", "id") on delete cascade
);
create index if not exists "incident_updates_parent_idx" on "better_supabase"."incident_updates" ("tenant_id", "incident_id", "created_at");
alter table "better_supabase"."incident_updates" enable row level security;
revoke all on "better_supabase"."incident_updates" from anon, authenticated;
grant select on "better_supabase"."incident_updates" to authenticated;
grant all on "better_supabase"."incident_updates" to service_role;
drop policy if exists "incident_updates_read" on "better_supabase"."incident_updates";
create policy "incident_updates_read" on "better_supabase"."incident_updates" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

create table if not exists "better_supabase"."incident_impacts" (
  "tenant_id" uuid not null,
  "incident_id" uuid not null,
  "component_id" uuid not null,
  "impact" text not null check ("impact" in ('maintenance', 'degraded', 'partial_outage', 'major_outage')),
  primary key ("incident_id", "component_id"),
  foreign key ("tenant_id", "incident_id") references "better_supabase"."incidents" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "component_id") references "better_supabase"."status_components" ("tenant_id", "id") on delete cascade
);
create index if not exists "incident_impacts_parent_idx" on "better_supabase"."incident_impacts" ("tenant_id", "incident_id");
create index if not exists "incident_impacts_component_idx" on "better_supabase"."incident_impacts" ("tenant_id", "component_id");
alter table "better_supabase"."incident_impacts" enable row level security;
revoke all on "better_supabase"."incident_impacts" from anon, authenticated;
grant select on "better_supabase"."incident_impacts" to authenticated;
grant all on "better_supabase"."incident_impacts" to service_role;
drop policy if exists "incident_impacts_read" on "better_supabase"."incident_impacts";
create policy "incident_impacts_read" on "better_supabase"."incident_impacts" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

create table if not exists "better_supabase"."incident_postmortems" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "incident_id" uuid not null unique,
  -- The only postmortem field a public incident's status page shows.
  "summary" text check ("summary" is null or length("summary") <= 4000),
  "impact" text check ("impact" is null or length("impact") <= 10000),
  "root_cause" text check ("root_cause" is null or length("root_cause") <= 10000),
  "resolution" text check ("resolution" is null or length("resolution") <= 10000),
  "action_items" jsonb not null default '[]'::jsonb check (jsonb_typeof("action_items") = 'array'),
  "status" text not null default 'draft' check ("status" in ('draft', 'published')),
  "published_at" timestamptz,
  "author_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "incident_id") references "better_supabase"."incidents" ("tenant_id", "id") on delete cascade
);
create index if not exists "incident_postmortems_tenant_idx" on "better_supabase"."incident_postmortems" ("tenant_id", "incident_id");
alter table "better_supabase"."incident_postmortems" enable row level security;
revoke all on "better_supabase"."incident_postmortems" from anon, authenticated;
grant select on "better_supabase"."incident_postmortems" to authenticated;
grant all on "better_supabase"."incident_postmortems" to service_role;
drop policy if exists "incident_postmortems_read" on "better_supabase"."incident_postmortems";
create policy "incident_postmortems_read" on "better_supabase"."incident_postmortems" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

-- One status page per organization. Anonymous visitors read it only through
-- public_status_page(slug), never through these tables.
create table if not exists "better_supabase"."status_pages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null unique,
  "slug" text not null unique check ("slug" ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "published" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."status_pages" enable row level security;
revoke all on "better_supabase"."status_pages" from anon, authenticated;
grant select on "better_supabase"."status_pages" to authenticated;
grant all on "better_supabase"."status_pages" to service_role;
drop policy if exists "status_pages_read" on "better_supabase"."status_pages";
create policy "status_pages_read" on "better_supabase"."status_pages" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')));

-- Sets each component's status to the worst impact of the open incidents on
-- it, and keeps the uptime history in step.
create or replace function "better_supabase"."incident_refresh_components"(component_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_component "better_supabase"."status_components"%rowtype;
  v_status text;
begin
  for v_component in
    select * from "better_supabase"."status_components" x where x."id" = any(incident_refresh_components.component_ids) for update
  loop
    select coalesce(
      (array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'])[max(array_position(array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'], im."impact"))],
      'operational'
    ) into v_status
    from "better_supabase"."incident_impacts" im
    join "better_supabase"."incidents" ii on ii."id" = im."incident_id"
    where im."component_id" = v_component."id" and ii."status" <> 'resolved';
    continue when v_status = v_component."status";
    update "better_supabase"."status_components" x set "status" = v_status, "updated_at" = now()
      where x."id" = v_component."id";
    update "better_supabase"."status_component_history" x set "ended_at" = now()
      where x."component_id" = v_component."id" and x."ended_at" is null;
    insert into "better_supabase"."status_component_history" ("tenant_id", "component_id", "status")
    values (v_component."tenant_id", v_component."id", v_status);
    null;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."incident_refresh_components"(uuid[]) from public, anon, authenticated;
grant execute on function "better_supabase"."incident_refresh_components"(uuid[]) to service_role;

-- Replaces an incident's impacts with [{ componentId, impact }] and refreshes
-- the components it touched before and after.
create or replace function "better_supabase"."incident_apply_impacts"(incident_id uuid, impacts jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_before uuid[];
  v_item jsonb;
  v_component uuid;
begin
  select * into v_row from "better_supabase"."incidents" x where x."id" = incident_apply_impacts.incident_id;
  if jsonb_typeof(coalesce(incident_apply_impacts.impacts, '[]'::jsonb)) <> 'array' then
    raise exception 'impacts must be an array' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  select coalesce(array_agg(x."component_id"), '{}') into v_before
    from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id";
  delete from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id";
  for v_item in select value from jsonb_array_elements(coalesce(incident_apply_impacts.impacts, '[]'::jsonb))
  loop
    v_component := nullif(v_item ->> 'componentId', '')::uuid;
    if not exists (
      select 1 from "better_supabase"."status_components" x where x."id" = v_component and x."tenant_id" = v_row."tenant_id"
    ) then
      raise exception 'status component not found' using errcode = 'P0002', hint = 'STATUS_COMPONENT_NOT_FOUND';
    end if;
    if coalesce(v_item ->> 'impact', '') not in ('maintenance', 'degraded', 'partial_outage', 'major_outage') then
      raise exception 'impact must be degraded, partial_outage, major_outage or maintenance' using errcode = '22023', hint = 'INCIDENTS_INVALID';
    end if;
    insert into "better_supabase"."incident_impacts" ("tenant_id", "incident_id", "component_id", "impact")
    values (v_row."tenant_id", v_row."id", v_component, v_item ->> 'impact')
    on conflict ("incident_id", "component_id") do update set "impact" = excluded."impact";
  end loop;
  perform "better_supabase"."incident_refresh_components"(
    v_before || array(select x."component_id" from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id")
  );
end;
$$;
revoke execute on function "better_supabase"."incident_apply_impacts"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."incident_apply_impacts"(uuid, jsonb) to service_role;

-- Creates a component by name, or changes one (component_id).
create or replace function "better_supabase"."save_status_component"(tenant uuid, name text, description text default null, group_name text default null, is_public boolean default true, sort_position integer default 0, component_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."status_components"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_status_component.tenant, 'incidents.manage'), false)) then
    raise exception 'not allowed to manage status components' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if nullif(trim(save_status_component.name), '') is null then
    raise exception 'a component needs a name' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if save_status_component.component_id is null then
    insert into "better_supabase"."status_components" ("tenant_id", "name", "description", "group_name", "public", "position")
    values (save_status_component.tenant, trim(save_status_component.name), save_status_component.description,
      nullif(trim(save_status_component.group_name), ''), coalesce(save_status_component.is_public, true), coalesce(save_status_component.sort_position, 0))
    returning * into v_row;
    insert into "better_supabase"."status_component_history" ("tenant_id", "component_id", "status")
    values (v_row."tenant_id", v_row."id", v_row."status");
  else
    update "better_supabase"."status_components" x set "name" = trim(save_status_component.name), "description" = save_status_component.description,
      "group_name" = nullif(trim(save_status_component.group_name), ''), "public" = coalesce(save_status_component.is_public, true),
      "position" = coalesce(save_status_component.sort_position, 0), "updated_at" = now()
      where x."id" = save_status_component.component_id and x."tenant_id" = save_status_component.tenant
      returning * into v_row;
    if not found then
      raise exception 'status component not found' using errcode = 'P0002', hint = 'STATUS_COMPONENT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'group', v_row."group_name", 'public', v_row."public", 'status', v_row."status", 'position', v_row."position", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_status_component"(uuid, text, text, text, boolean, integer, uuid) from public, anon;
grant execute on function "better_supabase"."save_status_component"(uuid, text, text, text, boolean, integer, uuid) to authenticated, service_role;

create or replace function "better_supabase"."delete_status_component"(component_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."status_components"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."status_components" x where x."id" = delete_status_component.component_id;
  if not found then
    raise exception 'status component not found' using errcode = 'P0002', hint = 'STATUS_COMPONENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.manage'), false)) then
    raise exception 'not allowed to manage status components' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."status_components" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'deleted', true);
end;
$$;
revoke execute on function "better_supabase"."delete_status_component"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_status_component"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_status_components"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'group', x."group_name", 'public', x."public", 'status', x."status", 'position', x."position", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."position", x."name"), '[]'::jsonb)
  from "better_supabase"."status_components" x
  where x."tenant_id" = list_status_components.tenant
$$;
revoke execute on function "better_supabase"."list_status_components"(uuid) from public, anon;
grant execute on function "better_supabase"."list_status_components"(uuid) to authenticated, service_role;

-- Opens an incident. attrs: title (required), description, severity (sev1
-- to sev4, default sev3), public, commanderId, message (the first timeline
-- update) and impacts ([{ componentId, impact }]).
drop function if exists "better_supabase"."open_incident"(uuid, jsonb, jsonb);
create or replace function "better_supabase"."open_incident"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_incident.tenant, 'incidents.write'), false)) then
    raise exception 'not allowed to open incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(open_incident.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if nullif(trim(open_incident.attrs ->> 'title'), '') is null then
    raise exception 'an incident needs a title' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if coalesce(open_incident.attrs ->> 'severity', 'sev3') not in ('sev1', 'sev2', 'sev3', 'sev4') then
    raise exception 'severity must be sev1, sev2, sev3 or sev4' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if open_incident.attrs ? 'commanderId' and open_incident.attrs ->> 'commanderId' is not null
    and not exists (select 1 from "better_supabase"."memberships" mm where mm."workspace_id" = open_incident.tenant and mm."user_id" = (open_incident.attrs ->> 'commanderId')::uuid) then
    raise exception 'the commander must be a member of the organization' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incidents" ("tenant_id", "title", "description", "severity", "public", "commander_id", "created_by")
  values (open_incident.tenant, trim(open_incident.attrs ->> 'title'), open_incident.attrs ->> 'description',
    coalesce(open_incident.attrs ->> 'severity', 'sev3'), coalesce((open_incident.attrs ->> 'public')::boolean, false),
    (open_incident.attrs ->> 'commanderId')::uuid, auth.uid())
  returning * into v_row;
  if nullif(trim(open_incident.attrs ->> 'message'), '') is not null then
    insert into "better_supabase"."incident_updates" ("tenant_id", "incident_id", "status", "body", "public", "author_id")
    values (v_row."tenant_id", v_row."id", v_row."status", trim(open_incident.attrs ->> 'message'), v_row."public", auth.uid());
  end if;
  perform "better_supabase"."incident_apply_impacts"(v_row."id", open_incident.attrs -> 'impacts');
  null;
  if v_row."commander_id" is not null and v_row."commander_id" is distinct from auth.uid() then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."open_incident"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."open_incident"(uuid, jsonb) to authenticated, service_role;

-- Changes an incident. attrs: title, description, severity, public and
-- commanderId; a key left out keeps its value. The status moves only
-- through post_incident_update.
drop function if exists "better_supabase"."update_incident"(uuid, jsonb, jsonb);
create or replace function "better_supabase"."update_incident"(incident_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."incidents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = update_incident.incident_id for update;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to change incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_incident.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if update_incident.attrs ? 'title' and nullif(trim(update_incident.attrs ->> 'title'), '') is null then
    raise exception 'an incident needs a title' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if update_incident.attrs ? 'severity' and coalesce(update_incident.attrs ->> 'severity', '') not in ('sev1', 'sev2', 'sev3', 'sev4') then
    raise exception 'severity must be sev1, sev2, sev3 or sev4' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if update_incident.attrs ->> 'commanderId' is not null
    and not exists (select 1 from "better_supabase"."memberships" mm where mm."workspace_id" = v_row."tenant_id" and mm."user_id" = (update_incident.attrs ->> 'commanderId')::uuid) then
    raise exception 'the commander must be a member of the organization' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  update "better_supabase"."incidents" x set
    "title" = case when update_incident.attrs ? 'title' then trim(update_incident.attrs ->> 'title') else x."title" end,
    "description" = case when update_incident.attrs ? 'description' then update_incident.attrs ->> 'description' else x."description" end,
    "severity" = case when update_incident.attrs ? 'severity' then update_incident.attrs ->> 'severity' else x."severity" end,
    "public" = case when update_incident.attrs ? 'public' then coalesce((update_incident.attrs ->> 'public')::boolean, false) else x."public" end,
    "commander_id" = case when update_incident.attrs ? 'commanderId' then (update_incident.attrs ->> 'commanderId')::uuid else x."commander_id" end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."update_incident"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_incident"(uuid, jsonb) to authenticated, service_role;

-- Adds a timeline update and moves the incident to its status (null keeps
-- the current one). is_public defaults to the incident's own flag; a public
-- update on a private incident still stays off the status page.
create or replace function "better_supabase"."post_incident_update"(incident_id uuid, status text, body text, is_public boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_from text;
  v_update "better_supabase"."incident_updates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = post_incident_update.incident_id for update;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to update incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if post_incident_update.status is not null and post_incident_update.status not in ('investigating', 'identified', 'monitoring', 'resolved') then
    raise exception 'status must be investigating, identified, monitoring or resolved' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if nullif(trim(post_incident_update.body), '') is null then
    raise exception 'an update needs a body' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  v_from := v_row."status";
  update "better_supabase"."incidents" x set
    "status" = coalesce(post_incident_update.status, x."status"),
    "resolved_at" = case
      when coalesce(post_incident_update.status, x."status") <> 'resolved' then null
      else coalesce(x."resolved_at", now())
    end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  insert into "better_supabase"."incident_updates" ("tenant_id", "incident_id", "status", "body", "public", "author_id")
  values (v_row."tenant_id", v_row."id", v_row."status", trim(post_incident_update.body),
    coalesce(post_incident_update.is_public, v_row."public"), auth.uid())
  returning * into v_update;
  if v_from is distinct from v_row."status" then
    perform "better_supabase"."incident_refresh_components"(
      array(select x."component_id" from "better_supabase"."incident_impacts" x where x."incident_id" = v_row."id")
    );
  end if;
  null;
  if v_row."status" = 'resolved' and v_from <> 'resolved' then
    null;
  end if;
  return jsonb_build_object('id', v_update."id", 'incidentId', v_update."incident_id", 'status', v_update."status", 'body', v_update."body", 'public', v_update."public", 'authorId', v_update."author_id", 'createdAt', v_update."created_at");
end;
$$;
revoke execute on function "better_supabase"."post_incident_update"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."post_incident_update"(uuid, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."set_incident_impacts"(incident_id uuid, impacts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."incidents"%rowtype;
begin
  select * into v_row from "better_supabase"."incidents" x where x."id" = set_incident_impacts.incident_id for update;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to change incidents' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  perform "better_supabase"."incident_apply_impacts"(v_row."id", set_incident_impacts.impacts);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'status', v_row."status", 'public', v_row."public", 'commanderId', v_row."commander_id", 'startedAt', v_row."started_at", 'resolvedAt', v_row."resolved_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."set_incident_impacts"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_incident_impacts"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_incident"(incident_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'severity', x."severity", 'status', x."status", 'public', x."public", 'commanderId', x."commander_id", 'startedAt', x."started_at", 'resolvedAt', x."resolved_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = x."id")) || jsonb_build_object(
    'updates', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'incidentId', y."incident_id", 'status', y."status", 'body', y."body", 'public', y."public", 'authorId', y."author_id", 'createdAt', y."created_at") order by y."created_at", y."id"), '[]'::jsonb) from "better_supabase"."incident_updates" y where y."incident_id" = x."id"),
    'postmortem', (select jsonb_build_object('id', z."id", 'incidentId', z."incident_id", 'summary', z."summary", 'impact', z."impact", 'rootCause', z."root_cause", 'resolution', z."resolution", 'actionItems', z."action_items", 'status', z."status", 'publishedAt', z."published_at", 'authorId', z."author_id", 'createdAt', z."created_at", 'updatedAt', z."updated_at") from "better_supabase"."incident_postmortems" z where z."incident_id" = x."id")
  )
  from "better_supabase"."incidents" x
  where x."id" = get_incident.incident_id
$$;
revoke execute on function "better_supabase"."get_incident"(uuid) from public, anon;
grant execute on function "better_supabase"."get_incident"(uuid) to authenticated, service_role;

-- The incidents, newest first. status: open, resolved or null for both;
-- before: the startedAt of the last row of the previous page.
create or replace function "better_supabase"."list_incidents"(tenant uuid, status text default null, severity text default null, component_id uuid default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(row_json order by started desc, id desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'severity', x."severity", 'status', x."status", 'public', x."public", 'commanderId', x."commander_id", 'startedAt', x."started_at", 'resolvedAt', x."resolved_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."status_components" ic on ic."id" = im."component_id" where im."incident_id" = x."id")) as row_json, x."started_at" as started, x."id" as id
    from "better_supabase"."incidents" x
    where x."tenant_id" = list_incidents.tenant
      and (list_incidents.status is null
        or (list_incidents.status = 'open' and x."status" <> 'resolved')
        or (list_incidents.status = 'resolved' and x."status" = 'resolved'))
      and (list_incidents.severity is null or x."severity" = list_incidents.severity)
      and (list_incidents.component_id is null or exists (
        select 1 from "better_supabase"."incident_impacts" y where y."incident_id" = x."id" and y."component_id" = list_incidents.component_id
      ))
      and (list_incidents.before is null or x."started_at" < list_incidents.before)
    order by x."started_at" desc, x."id" desc
    limit least(greatest(coalesce(list_incidents.page_size, 50), 1), 200)
  ) page
$$;
revoke execute on function "better_supabase"."list_incidents"(uuid, text, text, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_incidents"(uuid, text, text, uuid, timestamptz, integer) to authenticated, service_role;

-- Writes the incident's postmortem. attrs: summary, impact, rootCause,
-- resolution and actionItems ([{ title, ownerId, done }]); a key left out
-- keeps its value.
create or replace function "better_supabase"."save_postmortem"(incident_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = save_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to write postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(save_postmortem.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if save_postmortem.attrs ? 'actionItems' and jsonb_typeof(save_postmortem.attrs -> 'actionItems') is distinct from 'array' then
    raise exception 'actionItems must be an array' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incident_postmortems" ("tenant_id", "incident_id", "author_id")
  values (v_row."tenant_id", v_row."id", auth.uid())
  on conflict ("incident_id") do nothing;
  update "better_supabase"."incident_postmortems" x set
    "summary" = case when save_postmortem.attrs ? 'summary' then save_postmortem.attrs ->> 'summary' else x."summary" end,
    "impact" = case when save_postmortem.attrs ? 'impact' then save_postmortem.attrs ->> 'impact' else x."impact" end,
    "root_cause" = case when save_postmortem.attrs ? 'rootCause' then save_postmortem.attrs ->> 'rootCause' else x."root_cause" end,
    "resolution" = case when save_postmortem.attrs ? 'resolution' then save_postmortem.attrs ->> 'resolution' else x."resolution" end,
    "action_items" = case when save_postmortem.attrs ? 'actionItems' then save_postmortem.attrs -> 'actionItems' else x."action_items" end,
    "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actionItems', v_post."action_items", 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_postmortem"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_postmortem"(uuid, jsonb) to authenticated, service_role;

-- Publishes a resolved incident's postmortem. A public incident's status page
-- then shows its summary.
create or replace function "better_supabase"."publish_postmortem"(incident_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = publish_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.manage'), false)) then
    raise exception 'not allowed to publish postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if v_row."status" <> 'resolved' then
    raise exception 'only a resolved incident''s postmortem can be published' using errcode = '55000', hint = 'INCIDENT_NOT_RESOLVED';
  end if;
  update "better_supabase"."incident_postmortems" x set "status" = 'published', "published_at" = coalesce(x."published_at", now()), "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  if not found then
    raise exception 'the incident has no postmortem' using errcode = 'P0002', hint = 'POSTMORTEM_NOT_FOUND';
  end if;
  null;
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actionItems', v_post."action_items", 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_postmortem"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_postmortem"(uuid) to authenticated, service_role;

-- Creates or changes the organization's status page. A slug another
-- organization uses fails with STATUS_PAGE_SLUG_TAKEN.
create or replace function "better_supabase"."save_status_page"(tenant uuid, slug text, title text, description text default null, published boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."status_pages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_status_page.tenant, 'incidents.manage'), false)) then
    raise exception 'not allowed to manage the status page' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if save_status_page.slug is null or save_status_page.slug !~ '^[a-z0-9][a-z0-9-]{1,62}$' then
    raise exception 'the slug takes 2 to 63 lowercase letters, digits and dashes' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."status_pages" x where x."slug" = save_status_page.slug and x."tenant_id" <> save_status_page.tenant
  ) then
    raise exception 'another organization uses this slug' using errcode = '23505', hint = 'STATUS_PAGE_SLUG_TAKEN';
  end if;
  insert into "better_supabase"."status_pages" ("tenant_id", "slug", "title", "description", "published")
  values (save_status_page.tenant, save_status_page.slug, trim(save_status_page.title), save_status_page.description, coalesce(save_status_page.published, false))
  on conflict ("tenant_id") do update
    set "slug" = excluded."slug", "title" = excluded."title", "description" = excluded."description",
      "published" = excluded."published", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'slug', v_row."slug", 'title', v_row."title", 'description', v_row."description", 'published', v_row."published", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_status_page"(uuid, text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_status_page"(uuid, text, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."get_status_page"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'slug', x."slug", 'title', x."title", 'description', x."description", 'published', x."published", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."status_pages" x where x."tenant_id" = get_status_page.tenant
$$;
revoke execute on function "better_supabase"."get_status_page"(uuid) from public, anon;
grant execute on function "better_supabase"."get_status_page"(uuid) to authenticated, service_role;

-- The public status page behind a slug, for anyone: null unless the page is
-- published. It returns the page title and description, the public
-- components with their status and daily uptime over days (1 to 90, default
-- 90), and the public incidents (open ones, and those resolved in the
-- window) with their public updates and published postmortem summary.
create or replace function "better_supabase"."public_status_page"(slug text, days integer default 90)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_page "better_supabase"."status_pages"%rowtype;
  v_days integer := least(greatest(coalesce(public_status_page.days, 90), 1), 90);
  v_from timestamptz;
begin
  select * into v_page from "better_supabase"."status_pages" x where x."slug" = public_status_page.slug and x."published";
  if not found then
    return null;
  end if;
  v_from := (current_date - (v_days - 1))::timestamp at time zone 'UTC';
  return jsonb_build_object(
    'slug', v_page."slug",
    'title', v_page."title",
    'description', v_page."description",
    'days', v_days,
    'status', (
      select coalesce((array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'])[max(array_position(array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'], sc."status"))], 'operational')
      from "better_supabase"."status_components" sc
      where sc."tenant_id" = v_page."tenant_id" and sc."public"
    ),
    'components', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', pc."id",
        'name', pc."name",
        'description', pc."description",
        'group', pc."group_name",
        'status', pc."status",
        'uptimePercent', (
          select round(100 * (1 - coalesce(sum(extract(epoch from (
            least(coalesce(uh."ended_at", now()), now()) - greatest(uh."started_at", v_from)
          ))), 0) / greatest(extract(epoch from (now() - v_from)), 1))::numeric, 3)
          from "better_supabase"."status_component_history" uh
          where uh."component_id" = pc."id"
            and uh."status" in ('partial_outage', 'major_outage')
            and coalesce(uh."ended_at", now()) > v_from
        ),
        'uptime', (
          select jsonb_agg(jsonb_build_object('date', dd.d, 'status', coalesce(w.worst, 'operational'), 'downMinutes', coalesce(w.down, 0)) order by dd.d)
          from (select (current_date - n)::date as d from generate_series(0, v_days - 1) n) dd
          cross join lateral (
            select (array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'])[max(array_position(array['operational', 'maintenance', 'degraded', 'partial_outage', 'major_outage'], dh."status"))] as worst,
              (coalesce(sum(extract(epoch from (
                least(coalesce(dh."ended_at", now()), (dd.d + 1)::timestamp at time zone 'UTC')
                - greatest(dh."started_at", dd.d::timestamp at time zone 'UTC')
              ))) filter (where dh."status" in ('partial_outage', 'major_outage')), 0) / 60)::integer as down
            from "better_supabase"."status_component_history" dh
            where dh."component_id" = pc."id"
              and dh."started_at" < (dd.d + 1)::timestamp at time zone 'UTC'
              and coalesce(dh."ended_at", now()) > dd.d::timestamp at time zone 'UTC'
          ) w
        )
      ) order by pc."position", pc."name"), '[]'::jsonb)
      from "better_supabase"."status_components" pc
      where pc."tenant_id" = v_page."tenant_id" and pc."public"
    ),
    'incidents', (
      select coalesce(jsonb_agg(jsonb_build_object(
      'id', pi0."id",
      'title', pi0."title",
      'severity', pi0."severity",
      'status', pi0."status",
      'startedAt', pi0."started_at",
      'resolvedAt', pi0."resolved_at",
      'components', (
        select coalesce(jsonb_agg(jsonb_build_object('id', pc."id", 'name', pc."name", 'impact', pi."impact") order by pc."position", pc."name"), '[]'::jsonb)
        from "better_supabase"."incident_impacts" pi join "better_supabase"."status_components" pc on pc."id" = pi."component_id"
        where pi."incident_id" = pi0."id" and pc."public"
      ),
      'updates', (
        select coalesce(jsonb_agg(jsonb_build_object('status', pu."status", 'body', pu."body", 'createdAt', pu."created_at") order by pu."created_at" desc), '[]'::jsonb)
        from "better_supabase"."incident_updates" pu
        where pu."incident_id" = pi0."id" and pu."public"
      ),
      'postmortem', (
        select jsonb_build_object('summary', pp."summary", 'publishedAt', pp."published_at")
        from "better_supabase"."incident_postmortems" pp
        where pp."incident_id" = pi0."id" and pp."status" = 'published'
      )
    ) order by pi0."started_at" desc), '[]'::jsonb)
      from "better_supabase"."incidents" pi0
      where pi0."tenant_id" = v_page."tenant_id" and pi0."public"
        and (pi0."resolved_at" is null or pi0."resolved_at" >= v_from)
    )
  );
end;
$$;
revoke all on function "better_supabase"."public_status_page"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."public_status_page"(text, integer) to anon, authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."status_components";
create policy bsb_tenant_scope on "better_supabase"."status_components" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_component_history";
create policy bsb_tenant_scope on "better_supabase"."status_component_history" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."incidents";
create policy bsb_tenant_scope on "better_supabase"."incidents" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."incident_updates";
create policy bsb_tenant_scope on "better_supabase"."incident_updates" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."incident_impacts";
create policy bsb_tenant_scope on "better_supabase"."incident_impacts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."incident_postmortems";
create policy bsb_tenant_scope on "better_supabase"."incident_postmortems" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_pages";
create policy bsb_tenant_scope on "better_supabase"."status_pages" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('incidents.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_127_incidents.sql
-- better-supabase module: incidents
-- @bsb-block-data incidents
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('incidents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
