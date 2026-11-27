import type { ProjectsEvents } from "../../blocks/projects/events.ts";
import type {
  BlockSqlContext,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { fail, schemaPreamble, userGrant } from "../shared.ts";

const UPDATE = [
  "organizationId",
  "projectId",
  "updateId",
  "subjectType",
  "subjectId",
  "health",
  "actorId",
  "actorKind",
  "actorName",
] as const;

const INITIATIVE = [
  "organizationId",
  "initiativeId",
  "subjectType",
  "subjectId",
  "name",
  "actorId",
  "actorKind",
  "actorName",
] as const;

const EVENTS: BlockSqlEvents<ProjectsEvents> = {
  "project_update.created": { subject: "updates", payload: [...UPDATE] },
  "initiative.created": { subject: "initiatives", payload: [...INITIATIVE] },
  "initiative.updated": { subject: "initiatives", payload: [...INITIATIVE] },
  "initiative.archived": { subject: "initiatives", payload: [...INITIATIVE] },
  "initiative.deleted": { subject: "initiatives", payload: [...INITIATIVE] },
};

const NAMES: BlockSqlNames = {
  entities: {
    project_update: {
      table: "updates",
      singular: "project_update",
      subject: {
        title: "body",
        permissions: { read: "read", write: "manage" },
        realtime: true,
      },
    },
    initiative: {
      table: "initiatives",
      singular: "initiative",
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "manage" },
        search: { title: "name", body: ["description"] },
        realtime: true,
      },
    },
  },
  events: EVENTS,
  hooks: [],
  options: ["updateEvery"],
  tables: {
    updates: {
      name: "project_updates",
      app: {},
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        project: "project_id",
        author: "author_id",
        health: "health",
        body: "body",
        scope: "scope_count",
        started: "started_count",
        completed: "completed_count",
        createdAt: "created_at",
      },
    },
    initiatives: {
      name: "initiatives",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        description: "description",
        status: "status",
        priority: "priority",
        owner: "owner_id",
        targetOn: "target_on",
        parent: "parent_id",
        rank: "rank",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    links: {
      name: "initiative_projects",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        initiative: "initiative_id",
        project: "project_id",
        tenant: "tenant_id",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  const tasks = ctx.of("tasks");
  const project = tasks.table("projects");
  const projectId = tasks.col("projects", "id");
  const projectTenant = tasks.col("projects", "tenant");
  const u = (column: string): string => ctx.col("updates", column);
  const i = (column: string): string => ctx.col("initiatives", column);
  const l = (column: string): string => ctx.col("links", column);
  const actor = `, 'actorId', auth.uid(), 'actorKind', null, 'actorName', null`;
  const updateType = sqlString(entityType(ctx.resolved, "project_update"));
  const initiativeType = sqlString(entityType(ctx.resolved, "initiative"));

  const manage = ctx.permissionKey("manage", "initiatives.manage");
  const can = (tenant: string): string => ctx.scope.can(tenant, manage);

  const every = ctx.text("updateEvery", "");

  const reminder =
    every === ""
      ? ""
      : `
create or replace function ${ctx.fn("remind_project_updates")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_project record;
  v_count integer := 0;
begin
  for v_project in
    select p.${projectId} as id, p.${projectTenant} as tenant
    from ${project} p
    where p.${tasks.col("projects", "healthAt")} < now() - interval ${sqlString(every)}
  loop
    ${ctx.notify(`jsonb_build_object('type', 'project_update.missing', 'tenant', v_project.tenant, 'subject_type', ${sqlString("project")}, 'subject_id', v_project.id::text)`)}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${ctx.fn("remind_project_updates")}()`)}`;

  return `${schemaPreamble(ctx)}
create table if not exists ${ctx.table("updates")} (
  ${u("id")} uuid primary key default gen_random_uuid(),
  ${u("tenant")} ${ctx.idType} not null,
  ${u("project")} uuid not null references ${project} (${projectId}) on delete cascade,
  ${u("author")} uuid,
  ${u("health")} text not null check (${u("health")} in ('on_track', 'at_risk', 'off_track')),
  ${u("body")} text not null check (length(${u("body")}) between 1 and 20000),
  ${u("scope")} integer not null default 0,
  ${u("started")} integer not null default 0,
  ${u("completed")} integer not null default 0,
  ${u("createdAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("project_updates_project_idx")} on ${ctx.table("updates")} (${u("project")}, ${u("createdAt")} desc);

create table if not exists ${ctx.table("initiatives")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("name")} text not null check (length(${i("name")}) between 1 and 200),
  ${i("description")} text,
  ${i("status")} text not null default 'proposed' check (${i("status")} in ('proposed', 'planned', 'active', 'completed', 'canceled')),
  ${i("priority")} smallint not null default 0 check (${i("priority")} between 0 and 4),
  ${i("owner")} uuid,
  ${i("targetOn")} date,
  ${i("parent")} uuid references ${ctx.table("initiatives")} (${i("id")}) on delete set null,
  ${i("rank")} text collate "C" not null default 'V',
  ${i("archivedAt")} timestamptz,
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now()
);

create table if not exists ${ctx.table("links")} (
  ${l("initiative")} uuid not null references ${ctx.table("initiatives")} (${i("id")}) on delete cascade,
  ${l("project")} uuid not null references ${project} (${projectId}) on delete cascade,
  ${l("tenant")} ${ctx.idType} not null,
  primary key (${l("initiative")}, ${l("project")})
);

create or replace function ${ctx.fn("save_project_update")}(tenant ${ctx.idType}, project uuid, health text, body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
  v_row ${ctx.table("updates")};
  v_scope integer;
  v_started integer;
  v_completed integer;
begin
  if save_project_update.health not in ('on_track', 'at_risk', 'off_track') then
    ${fail("PROJECT_UPDATE_INVALID", "health must be on_track, at_risk or off_track", "22023")}
  end if;
  if not exists (select 1 from ${project} p where p.${projectId} = save_project_update.project and p.${projectTenant} = save_project_update.tenant) then
    ${fail("PROJECT_NOT_FOUND", "project not found", "P0002")}
  end if;
  select count(*)::integer,
    count(*) filter (where t.${tasks.col("items", "state")} = 'started')::integer,
    count(*) filter (where t.${tasks.col("items", "state")} = 'completed')::integer
  into v_scope, v_started, v_completed
  from ${tasks.table("items")} t
  where t.${tasks.col("items", "project")} = save_project_update.project;
  insert into ${ctx.table("updates")} (${u("tenant")}, ${u("project")}, ${u("author")}, ${u("health")}, ${u("body")}, ${u("scope")}, ${u("started")}, ${u("completed")})
  values (save_project_update.tenant, save_project_update.project, auth.uid(), save_project_update.health, save_project_update.body, v_scope, v_started, v_completed)
  returning * into v_row;
  perform ${tasks.fn("set_project_health")}(save_project_update.project, save_project_update.health);
  ${ctx.record({
    type: "project_update.created",
    payload: `jsonb_build_object('organizationId', v_row.${u("tenant")}, 'projectId', v_row.${u("project")}, 'updateId', v_row.${u("id")}, 'subjectType', ${updateType}, 'subjectId', v_row.${u("id")}::text, 'health', v_row.${u("health")}${actor})`,
    subject: `'updates/' || v_row.${u("id")}::text`,
    tenant: `v_row.${u("tenant")}::text`,
    row: "v_row",
    audit: false,
  })}
  ${ctx.notify(`jsonb_build_object('type', 'project_update.created', 'tenant', v_row.${u("tenant")}, 'subject_type', ${updateType}, 'subject_id', v_row.${u("project")}::text)`)}
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${ctx.fn("save_project_update")}(${ctx.idType}, uuid, text, text)`)}

create or replace function ${ctx.fn("page_project_updates")}(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.${u("createdAt")} desc), '[]'::jsonb)
  from ${ctx.table("updates")} x where x.${u("project")} = page_project_updates.project
$$;
${userGrant(`${ctx.fn("page_project_updates")}(uuid)`)}

create or replace function ${ctx.fn("save_initiative")}(tenant ${ctx.idType}, id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${ctx.table("initiatives")};
begin
  if not (${can("save_initiative.tenant")}) then
    ${fail("INITIATIVE_FORBIDDEN", "not allowed to change initiatives", "42501")}
  end if;
  if save_initiative.id is null then
    insert into ${ctx.table("initiatives")} (${i("tenant")}, ${i("name")}, ${i("description")}, ${i("status")}, ${i("priority")}, ${i("owner")}, ${i("targetOn")}, ${i("parent")}, ${i("rank")})
    values (save_initiative.tenant, save_initiative.attrs ->> 'name', nullif(save_initiative.attrs ->> 'description', ''), coalesce(nullif(save_initiative.attrs ->> 'status', ''), 'proposed'), coalesce((save_initiative.attrs ->> 'priority')::smallint, 0), nullif(save_initiative.attrs ->> 'ownerId', '')::uuid, nullif(save_initiative.attrs ->> 'targetOn', '')::date, nullif(save_initiative.attrs ->> 'parentId', '')::uuid, coalesce(nullif(save_initiative.attrs ->> 'rank', ''), 'V'))
    returning * into v_row;
    ${ctx.record({
      type: "initiative.created",
      payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'initiativeId', v_row.${i("id")}, 'subjectType', ${initiativeType}, 'subjectId', v_row.${i("id")}::text, 'name', v_row.${i("name")}${actor})`,
      subject: `'initiatives/' || v_row.${i("id")}::text`,
      tenant: `v_row.${i("tenant")}::text`,
      row: "v_row",
      audit: false,
    })}
  else
    update ${ctx.table("initiatives")} x set
      ${i("name")} = coalesce(save_initiative.attrs ->> 'name', x.${i("name")}),
      ${i("description")} = case when save_initiative.attrs ? 'description' then nullif(save_initiative.attrs ->> 'description', '') else x.${i("description")} end,
      ${i("status")} = coalesce(nullif(save_initiative.attrs ->> 'status', ''), x.${i("status")}),
      ${i("priority")} = coalesce((save_initiative.attrs ->> 'priority')::smallint, x.${i("priority")}),
      ${i("updatedAt")} = now()
    where x.${i("id")} = save_initiative.id and x.${i("tenant")} = save_initiative.tenant
      and (save_initiative.attrs ->> 'parentId' is null or not exists (
        with recursive chain as (
          select parent.${i("id")} as id, parent.${i("parent")} as parent
          from ${ctx.table("initiatives")} parent
          where parent.${i("id")} = (save_initiative.attrs ->> 'parentId')::uuid
          union all
          select next.${i("id")}, next.${i("parent")}
          from ${ctx.table("initiatives")} next
          join chain on next.${i("id")} = chain.parent
        )
        select 1 from chain where chain.id = x.${i("id")}
      ))
    returning * into v_row;
    if v_row.${i("id")} is null then
      ${fail("INITIATIVE_NOT_FOUND", "initiative not found", "P0002")}
    end if;
    ${ctx.record({
      type: "initiative.updated",
      payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'initiativeId', v_row.${i("id")}, 'subjectType', ${initiativeType}, 'subjectId', v_row.${i("id")}::text, 'name', v_row.${i("name")}${actor})`,
      subject: `'initiatives/' || v_row.${i("id")}::text`,
      tenant: `v_row.${i("tenant")}::text`,
      row: "v_row",
      audit: false,
    })}
  end if;
  return to_jsonb(v_row);
end;
$$;
${userGrant(`${ctx.fn("save_initiative")}(${ctx.idType}, uuid, jsonb)`)}

create or replace function ${ctx.fn("get_initiative")}(initiative uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('health', (
    select u.${u("health")} from ${ctx.table("links")} link
    join ${ctx.table("updates")} u on u.${u("project")} = link.${l("project")}
    where link.${l("initiative")} = x.${i("id")}
    order by u.${u("createdAt")} desc
    limit 1
  ))
  from ${ctx.table("initiatives")} x where x.${i("id")} = get_initiative.initiative
$$;
${userGrant(`${ctx.fn("get_initiative")}(uuid)`)}

create or replace function ${ctx.fn("page_initiatives")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.${i("rank")}, x.${i("name")}), '[]'::jsonb)
  from ${ctx.table("initiatives")} x
  where x.${i("tenant")} = page_initiatives.tenant and x.${i("archivedAt")} is null
$$;
${userGrant(`${ctx.fn("page_initiatives")}(${ctx.idType})`)}

create or replace function ${ctx.fn("archive_initiative")}(initiative uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${ctx.table("initiatives")};
begin
  update ${ctx.table("initiatives")} x set
    ${i("archivedAt")} = case when archive_initiative.archived then coalesce(x.${i("archivedAt")}, now()) end,
    ${i("updatedAt")} = now()
  where x.${i("id")} = archive_initiative.initiative and ${can(`x.${i("tenant")}`)}
  returning * into v_row;
  if v_row.${i("id")} is null then
    return false;
  end if;
  ${ctx.record({
    type: "initiative.archived",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'initiativeId', v_row.${i("id")}, 'subjectType', ${initiativeType}, 'subjectId', v_row.${i("id")}::text, 'name', v_row.${i("name")}${actor})`,
    subject: `'initiatives/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}::text`,
    row: "v_row",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("archive_initiative")}(uuid, boolean)`)}

create or replace function ${ctx.fn("remove_initiative")}(initiative uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${ctx.table("initiatives")};
begin
  delete from ${ctx.table("initiatives")} x
  where x.${i("id")} = remove_initiative.initiative and x.${i("archivedAt")} is not null and ${can(`x.${i("tenant")}`)}
  returning * into v_row;
  if v_row.${i("id")} is null then
    return false;
  end if;
  ${ctx.record({
    type: "initiative.deleted",
    payload: `jsonb_build_object('organizationId', v_row.${i("tenant")}, 'initiativeId', v_row.${i("id")}, 'subjectType', ${initiativeType}, 'subjectId', v_row.${i("id")}::text, 'name', v_row.${i("name")}${actor})`,
    subject: `'initiatives/' || v_row.${i("id")}::text`,
    tenant: `v_row.${i("tenant")}::text`,
    row: "v_row",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("remove_initiative")}(uuid)`)}

create or replace function ${ctx.fn("link_initiative_project")}(initiative uuid, project uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${i("tenant")} into v_tenant from ${ctx.table("initiatives")} x where x.${i("id")} = link_initiative_project.initiative;
  if v_tenant is null then
    return false;
  end if;
  insert into ${ctx.table("links")} (${l("initiative")}, ${l("project")}, ${l("tenant")})
  values (link_initiative_project.initiative, link_initiative_project.project, v_tenant)
  on conflict do nothing;
  return true;
end;
$$;
${userGrant(`${ctx.fn("link_initiative_project")}(uuid, uuid)`)}
${reminder}`;
}

export const PROJECTS: BlockSqlDefinition = {
  name: "projects",
  scopes: ["tenant"],
  title: "Projects",
  description:
    "Project updates with a health snapshot, and initiatives that group projects. Tasks owns the project, milestone and iteration rows.",
  requires: ["memberships", "permissions", "subjects", "tasks"],
  integrates: ["notifications", "housekeeping", "outbox"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract: (ctx) => [
    {
      name: "save_project_update",
      args: ["{id}", "uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "page_project_updates", args: ["uuid"], returns: "jsonb" },
    {
      name: "save_initiative",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_initiative", args: ["uuid"], returns: "jsonb" },
    { name: "page_initiatives", args: ["{id}"], returns: "jsonb" },
    {
      name: "archive_initiative",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "remove_initiative", args: ["uuid"], returns: "boolean" },
    {
      name: "link_initiative_project",
      args: ["uuid", "uuid"],
      returns: "boolean",
    },
    ...(ctx.text("updateEvery", "") === ""
      ? []
      : [{ name: "remind_project_updates", args: [], returns: "integer" }]),
  ],
  build,
};
