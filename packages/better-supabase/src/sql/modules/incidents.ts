import type { IncidentsEvents } from "../../blocks/incidents/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { tableMoves } from "../table-renames.ts";
import { copyActionItems } from "./incidents-data.ts";
import { incidentsFunctions } from "./incidents-functions.ts";
import {
  INCIDENT_RESERVED,
  INCIDENT_SEVERITIES,
  INCIDENT_STATUSES,
  COMPONENT_STATUSES,
} from "./incidents-shared.ts";
import { statusPageFunctions } from "./incidents-status-page.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<IncidentsEvents> = {
  "incident.opened": {
    subject: "incidents",
    payload: [
      "organizationId",
      "incidentId",
      "title",
      "severity",
      "status",
      "public",
    ],
  },
  "incident.updated": {
    subject: "incidents",
    payload: ["organizationId", "incidentId", "updateId", "status", "public"],
  },
  "incident.resolved": {
    subject: "incidents",
    payload: ["organizationId", "incidentId", "severity"],
  },
  "incident_postmortem.published": {
    subject: "incidents",
    payload: ["organizationId", "postmortemId", "incidentId"],
  },
  "status_component.changed": {
    subject: "status-components",
    payload: [
      "organizationId",
      "statusComponentId",
      "status",
      "previousStatus",
    ],
  },
};

const NAMES: BlockSqlNames = {
  migrations: tableMoves("incidents", 1),
  entities: {
    incident: {
      table: "incidents",
      singular: "incident",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    status_component: { table: "components", singular: "status_component" },
    incident_postmortem: {
      table: "postmortems",
      singular: "incident_postmortem",
      formerly: "postmortem",
    },
    status_page: { table: "pages", singular: "status_page" },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    components: {
      name: "incident_status_components",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        description: "description",
        group: "group_name",
        public: "public",
        status: "status",
        position: "position",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "group", "position", "createdAt", "updatedAt"],
      typed: ["status"],
    },
    history: {
      name: "incident_status_component_history",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        component: "component_id",
        status: "status",
        startedAt: "started_at",
        endedAt: "ended_at",
      },
      typed: ["status"],
    },
    incidents: {
      name: "incidents",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        description: "description",
        severity: "severity",
        status: "status",
        public: "public",
        commander: "commander_id",
        startedAt: "started_at",
        resolvedAt: "resolved_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "description",
        "commander",
        "createdBy",
        "createdAt",
        "updatedAt",
      ],
      typed: ["severity", "status"],
    },
    updates: {
      name: "incident_updates",
      app: {},
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        incident: "incident_id",
        status: "status",
        body: "body",
        public: "public",
        author: "author_id",
        createdAt: "created_at",
      },
      typed: ["status"],
    },
    impacts: {
      name: "incident_impacts",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        incident: "incident_id",
        component: "component_id",
        impact: "impact",
      },
      typed: ["impact"],
    },
    postmortems: {
      name: "incident_postmortems",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        incident: "incident_id",
        summary: "summary",
        impact: "impact",
        rootCause: "root_cause",
        resolution: "resolution",
        actionItems: "action_items",
        status: "status",
        publishedAt: "published_at",
        author: "author_id",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "impact",
        "rootCause",
        "resolution",
        "actionItems",
        "author",
        "createdAt",
        "updatedAt",
      ],
      typed: ["status"],
    },
    // With the tasks block: a postmortem's action items, one task each.
    actions: {
      name: "incident_postmortem_actions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        postmortem: "postmortem_id",
        task: "task_id",
        createdAt: "created_at",
      },
      optional: ["createdAt"],
    },
    pages: {
      name: "incident_status_pages",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        slug: "slug",
        title: "title",
        description: "description",
        published: "published",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "createdAt", "updatedAt"],
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const components = ctx.table("components");
  const history = ctx.table("history");
  const incidents = ctx.table("incidents");
  const updates = ctx.table("updates");
  const impacts = ctx.table("impacts");
  const postmortems = ctx.table("postmortems");
  const pages = ctx.table("pages");
  const c = (column: string): string => ctx.col("components", column);
  const h = (column: string): string => ctx.col("history", column);
  const i = (column: string): string => ctx.col("incidents", column);
  const u = (column: string): string => ctx.col("updates", column);
  const m = (column: string): string => ctx.col("impacts", column);
  const pm = (column: string): string => ctx.col("postmortems", column);
  const g = (column: string): string => ctx.col("pages", column);
  const read = ctx.permission("read", moduleOperations("incidents").read);
  const extras = ctx.extraColumns("incidents", INCIDENT_RESERVED);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const readPolicy = (logical: string, tenant: string): string => {
    const policy = ctx.owns(logical)
      ? name(logical, "read")
      : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`);

    return renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: policy,
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, read),
      }),
      { drop: true, target: ctx.table(logical) },
    );
  };

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  return `
-- The services a status page reports on. status follows the worst impact of
-- the open incidents on the component; nothing else writes it.
create table if not exists ${components} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 200),${opt("components", "description", () => `${c("description")} text check (${c("description")} is null or length(${c("description")}) <= 2000)`)}${opt("components", "group", () => `${c("group")} text check (${c("group")} is null or length(${c("group")}) <= 100)`)}
  -- Whether the component shows on the public status page.
  ${c("public")} boolean not null default true,
  ${c("status")} text not null default 'operational' check (${c("status")} in (${list(COMPONENT_STATUSES)})),${opt("components", "position", () => `${c("position")} integer not null default 0`)}${opt("components", "createdAt", () => `${c("createdAt")} timestamptz not null default now()`)}${opt("components", "updatedAt", () => `${c("updatedAt")} timestamptz not null default now()`)}
  unique (${c("tenant")}, ${c("id")})
);${appKey("components", "tenant_id", `${c("tenant")}, ${c("id")}`)}
create index if not exists ${name("components", "tenant_idx")} on ${components} (${c("tenant")}${ctx.has("components", "position") ? `, ${c("position")}` : ""});
${lockTable(components, { read: true })}
${readPolicy("components", c("tenant"))}

-- One row per status a component held, for the uptime history.
create table if not exists ${history} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("component")} uuid not null,
  ${h("status")} text not null check (${h("status")} in (${list(COMPONENT_STATUSES)})),
  ${h("startedAt")} timestamptz not null default now(),
  ${h("endedAt")} timestamptz,
  check (${h("endedAt")} is null or ${h("endedAt")} >= ${h("startedAt")}),
  foreign key (${h("tenant")}, ${h("component")}) references ${components} (${c("tenant")}, ${c("id")}) on delete cascade
);
create index if not exists ${name("history", "component_idx")} on ${history} (${h("tenant")}, ${h("component")}, ${h("startedAt")});
create unique index if not exists ${name("history", "open_idx")} on ${history} (${h("component")}) where ${h("endedAt")} is null;
${lockTable(history, { read: true })}
${readPolicy("history", h("tenant"))}

create table if not exists ${incidents} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("title")} text not null check (length(${i("title")}) between 1 and 200),${
    ctx.has("incidents", "description")
      ? `
  -- Internal detail; the public status page never shows it.
  ${i("description")} text check (${i("description")} is null or length(${i("description")}) <= 10000),`
      : ""
  }
  ${i("severity")} text not null default 'sev3' check (${i("severity")} in (${list(INCIDENT_SEVERITIES)})),
  ${i("status")} text not null default 'investigating' check (${i("status")} in (${list(INCIDENT_STATUSES)})),
  -- Whether the incident, its public updates and its published postmortem
  -- summary show on the public status page.
  ${i("public")} boolean not null default false,${opt("incidents", "commander", () => `${i("commander")} uuid`)}
  ${i("startedAt")} timestamptz not null default now(),
  ${i("resolvedAt")} timestamptz,${opt("incidents", "createdBy", () => `${i("createdBy")} uuid`)}${opt("incidents", "createdAt", () => `${i("createdAt")} timestamptz not null default now()`)}${opt("incidents", "updatedAt", () => `${i("updatedAt")} timestamptz not null default now()`)}
  check ((${i("status")} = 'resolved') = (${i("resolvedAt")} is not null)),
  unique (${i("tenant")}, ${i("id")})
);${addExtraColumns(incidents, extras)}${appKey("incidents", "tenant_id", `${i("tenant")}, ${i("id")}`)}
create index if not exists ${name("incidents", "tenant_idx")} on ${incidents} (${i("tenant")}, ${i("startedAt")} desc);
create index if not exists ${name("incidents", "open_idx")} on ${incidents} (${i("tenant")}) where ${i("status")} <> 'resolved';${
    ctx.has("incidents", "commander")
      ? `
create index if not exists ${name("incidents", "commander_idx")} on ${incidents} (${i("tenant")}, ${i("commander")}) where ${i("commander")} is not null;`
      : ""
  }
${lockTable(incidents, { read: true })}
${readPolicy("incidents", i("tenant"))}

-- The status timeline: each update sets the incident's status.
create table if not exists ${updates} (
  ${u("id")} uuid primary key default gen_random_uuid(),
  ${u("tenant")} ${ctx.idType} not null,
  ${u("incident")} uuid not null,
  ${u("status")} text not null check (${u("status")} in (${list(INCIDENT_STATUSES)})),
  ${u("body")} text not null check (length(${u("body")}) between 1 and 10000),
  ${u("public")} boolean not null default false,
  ${u("author")} uuid,
  -- clock_timestamp keeps the timeline in order when one transaction posts
  -- several updates.
  ${u("createdAt")} timestamptz not null default clock_timestamp(),
  foreign key (${u("tenant")}, ${u("incident")}) references ${incidents} (${i("tenant")}, ${i("id")}) on delete cascade
);
create index if not exists ${name("updates", "parent_idx")} on ${updates} (${u("tenant")}, ${u("incident")}, ${u("createdAt")});
${lockTable(updates, { read: true })}
${readPolicy("updates", u("tenant"))}

create table if not exists ${impacts} (
  ${m("tenant")} ${ctx.idType} not null,
  ${m("incident")} uuid not null,
  ${m("component")} uuid not null,
  ${m("impact")} text not null check (${m("impact")} in (${list(COMPONENT_STATUSES.slice(1))})),
  primary key (${m("incident")}, ${m("component")}),
  foreign key (${m("tenant")}, ${m("incident")}) references ${incidents} (${i("tenant")}, ${i("id")}) on delete cascade,
  foreign key (${m("tenant")}, ${m("component")}) references ${components} (${c("tenant")}, ${c("id")}) on delete cascade
);${appKey("impacts", "incident_component", `${m("incident")}, ${m("component")}`)}
create index if not exists ${name("impacts", "parent_idx")} on ${impacts} (${m("tenant")}, ${m("incident")});
create index if not exists ${name("impacts", "component_idx")} on ${impacts} (${m("tenant")}, ${m("component")});
${lockTable(impacts, { read: true })}
${readPolicy("impacts", m("tenant"))}

create table if not exists ${postmortems} (
  ${pm("id")} uuid primary key default gen_random_uuid(),
  ${pm("tenant")} ${ctx.idType} not null,
  ${pm("incident")} uuid not null unique,
  -- The only postmortem field a public incident's status page shows.
  ${pm("summary")} text check (${pm("summary")} is null or length(${pm("summary")}) <= 4000),${opt("postmortems", "impact", () => `${pm("impact")} text check (${pm("impact")} is null or length(${pm("impact")}) <= 10000)`)}${opt("postmortems", "rootCause", () => `${pm("rootCause")} text check (${pm("rootCause")} is null or length(${pm("rootCause")}) <= 10000)`)}${opt("postmortems", "resolution", () => `${pm("resolution")} text check (${pm("resolution")} is null or length(${pm("resolution")}) <= 10000)`)}${opt("postmortems", "actionItems", () => `${pm("actionItems")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${pm("actionItems")}) = 'array')`)}
  ${pm("status")} text not null default 'draft' check (${pm("status")} in ('draft', 'published')),
  ${pm("publishedAt")} timestamptz,${opt("postmortems", "author", () => `${pm("author")} uuid`)}${opt("postmortems", "createdAt", () => `${pm("createdAt")} timestamptz not null default now()`)}${opt("postmortems", "updatedAt", () => `${pm("updatedAt")} timestamptz not null default now()`)}
  foreign key (${pm("tenant")}, ${pm("incident")}) references ${incidents} (${i("tenant")}, ${i("id")}) on delete cascade
);${appKey("postmortems", "incident", pm("incident"))}
create index if not exists ${name("postmortems", "tenant_idx")} on ${postmortems} (${pm("tenant")}, ${pm("incident")});
${lockTable(postmortems, { read: true })}
${readPolicy("postmortems", pm("tenant"))}
${actionsTable(ctx, readPolicy, appKey)}
-- One status page per organization. Anonymous visitors read it only through
-- public_status_page(slug), never through these tables.
create table if not exists ${pages} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null unique,
  ${g("slug")} text not null unique check (${g("slug")} ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  ${g("title")} text not null check (length(${g("title")}) between 1 and 200),${opt("pages", "description", () => `${g("description")} text check (${g("description")} is null or length(${g("description")}) <= 2000)`)}
  ${g("published")} boolean not null default false${
    ctx.has("pages", "createdAt")
      ? `,
  ${g("createdAt")} timestamptz not null default now()`
      : ""
  }${
    ctx.has("pages", "updatedAt")
      ? `,
  ${g("updatedAt")} timestamptz not null default now()`
      : ""
  }
);${appKey("pages", "tenant", g("tenant"))}${appKey("pages", "slug", g("slug"))}
${lockTable(pages, { read: true })}
${readPolicy("pages", g("tenant"))}
`;
}

/** The postmortem action items, a task each, with the tasks module. */
function actionsTable(
  ctx: BlockSqlContext,
  readPolicy: (logical: string, tenant: string) => string,
  appKey: (logical: string, what: string, columns: string) => string,
): string {
  if (!ctx.installed("tasks")) {
    return "";
  }

  const actions = ctx.table("actions");
  const a = (column: string): string => ctx.col("actions", column);
  const tasks = ctx.of("tasks");

  return `
-- A postmortem's action items: each one is a task, so it is assigned, due
-- and closed in the tasks block.
create table if not exists ${actions} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("postmortem")} uuid not null references ${ctx.table("postmortems")} (${ctx.col("postmortems", "id")}) on delete cascade,
  ${a("task")} uuid not null references ${tasks.table("items")} (${tasks.col("items", "id")}) on delete cascade,${ctx.has("actions", "createdAt") ? `\n  ${a("createdAt")} timestamptz not null default now(),` : ""}
  unique (${a("postmortem")}, ${a("task")})
);${appKey("actions", "postmortem_task", `${a("postmortem")}, ${a("task")}`)}
create index if not exists ${sqlIdent(`${ctx.tableName("actions").name}_task_idx`)} on ${actions} (${a("task")});
create index if not exists ${sqlIdent(`${ctx.tableName("actions").name}_tenant_idx`)} on ${actions} (${a("tenant")});
${lockTable(actions, { read: true })}
${readPolicy("actions", a("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Incidents: severity, a status timeline, affected components, postmortems,
-- and a public status page read through one narrow function.
${tables(ctx)}${incidentsFunctions(ctx)}${statusPageFunctions(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("incidents", INCIDENT_RESERVED),
  ).contract;

  return [
    {
      name: "save_status_component",
      args: ["{id}", "text", "text", "text", "boolean", "integer", "uuid"],
      returns: "jsonb",
    },
    { name: "delete_status_component", args: ["uuid"], returns: "jsonb" },
    { name: "list_status_components", args: ["{id}"], returns: "jsonb" },
    {
      name: "open_incident",
      args: ["{id}", "jsonb", ...extra],
      returns: "jsonb",
    },
    {
      name: "update_incident",
      args: ["uuid", "jsonb", ...extra],
      returns: "jsonb",
    },
    {
      name: "post_incident_update",
      args: ["uuid", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "set_incident_impacts", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "get_incident", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_incidents",
      args: ["{id}", "text", "text", "uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    {
      name: "save_incident_postmortem",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "publish_incident_postmortem", args: ["uuid"], returns: "jsonb" },
    ...(ctx.installed("tasks")
      ? [
          {
            name: "add_incident_postmortem_action",
            args: ["uuid", "text", "uuid", "timestamptz"],
            returns: "jsonb",
          },
          {
            name: "remove_incident_postmortem_action",
            args: ["uuid"],
            returns: "jsonb",
          },
        ]
      : []),
    {
      name: "save_status_page",
      args: ["{id}", "text", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "get_status_page", args: ["{id}"], returns: "jsonb" },
    { name: "public_status_page", args: ["text", "integer"], returns: "jsonb" },
  ];
}

export const INCIDENTS: BlockSqlDefinition = {
  internal: [
    "incident_apply_impacts",
    "incident_postmortem_action_list",
    "incident_refresh_components",
  ],
  name: "incidents",
  scopes: ["tenant"],
  title: "Incidents",
  description:
    "Incidents with a severity, a status timeline of updates, the components they affect and a postmortem, plus a public status page: component status, public incident updates and uptime history, readable anonymously through one function that returns only the fields marked public.",
  requires: ["memberships", "permissions"],
  integrates: ["notifications", "outbox", "audit", "tasks"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  names: NAMES,
  contract,
  build,
  data: copyActionItems,
};
