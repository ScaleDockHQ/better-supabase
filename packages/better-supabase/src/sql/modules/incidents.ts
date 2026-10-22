import type { IncidentsEvents } from "../../blocks/incidents/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import { incidentsFunctions } from "./incidents-functions.ts";
import { statusPageFunctions } from "./incidents-status-page.ts";

const EVENTS: ModuleEvents<IncidentsEvents> = {
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
  "postmortem.published": {
    subject: "incidents",
    payload: ["organizationId", "postmortemId", "incidentId"],
  },
  "status_component.changed": {
    subject: "status-components",
    payload: ["organizationId", "statusComponentId", "status", "previousStatus"],
  },
};

const NAMES: ModuleNames = {
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
    postmortem: { table: "postmortems", singular: "postmortem" },
    status_page: { table: "pages", singular: "status_page" },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    components: {
      name: "status_components",
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
    },
    history: {
      name: "status_component_history",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        component: "component_id",
        status: "status",
        startedAt: "started_at",
        endedAt: "ended_at",
      },
    },
    incidents: {
      name: "incidents",
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
    },
    updates: {
      name: "incident_updates",
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
    },
    impacts: {
      name: "incident_impacts",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        incident: "incident_id",
        component: "component_id",
        impact: "impact",
      },
    },
    postmortems: {
      name: "incident_postmortems",
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
    },
    pages: {
      name: "status_pages",
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
    },
  },
};

/** The keys the incident reads return next to the extra columns. */
export const INCIDENT_RESERVED = [
  "fields",
  "updates",
  "impacts",
  "postmortem",
] as const;

export const INCIDENT_SEVERITIES = ["sev1", "sev2", "sev3", "sev4"] as const;

export const INCIDENT_STATUSES = [
  "investigating",
  "identified",
  "monitoring",
  "resolved",
] as const;

/** Component statuses, least to most severe. */
export const COMPONENT_STATUSES = [
  "operational",
  "maintenance",
  "degraded",
  "partial_outage",
  "major_outage",
] as const;

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: ModuleContext): string {
  if (!ctx.manages) {
    return "";
  }

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

  const readPolicy = (logical: string, tenant: string): string =>
    `drop policy if exists ${name(logical, "read")} on ${ctx.table(logical)};
create policy ${name(logical, "read")} on ${ctx.table(logical)} for select to authenticated
  using (${ctx.scope.check(tenant, read)});`;

  return `
-- The services a status page reports on. status follows the worst impact of
-- the open incidents on the component; nothing else writes it.
create table if not exists ${components} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 200),
  ${c("description")} text check (${c("description")} is null or length(${c("description")}) <= 2000),
  ${c("group")} text check (${c("group")} is null or length(${c("group")}) <= 100),
  -- Whether the component shows on the public status page.
  ${c("public")} boolean not null default true,
  ${c("status")} text not null default 'operational' check (${c("status")} in (${list(COMPONENT_STATUSES)})),
  ${c("position")} integer not null default 0,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  unique (${c("tenant")}, ${c("id")})
);
create index if not exists ${name("components", "tenant_idx")} on ${components} (${c("tenant")}, ${c("position")});
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
  ${i("title")} text not null check (length(${i("title")}) between 1 and 200),
  -- Internal detail; the public status page never shows it.
  ${i("description")} text check (${i("description")} is null or length(${i("description")}) <= 10000),
  ${i("severity")} text not null default 'sev3' check (${i("severity")} in (${list(INCIDENT_SEVERITIES)})),
  ${i("status")} text not null default 'investigating' check (${i("status")} in (${list(INCIDENT_STATUSES)})),
  -- Whether the incident, its public updates and its published postmortem
  -- summary show on the public status page.
  ${i("public")} boolean not null default false,
  ${i("commander")} uuid,
  ${i("startedAt")} timestamptz not null default now(),
  ${i("resolvedAt")} timestamptz,
  ${i("createdBy")} uuid,
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  check ((${i("status")} = 'resolved') = (${i("resolvedAt")} is not null)),
  unique (${i("tenant")}, ${i("id")})
);${addExtraColumns(incidents, extras)}
create index if not exists ${name("incidents", "tenant_idx")} on ${incidents} (${i("tenant")}, ${i("startedAt")} desc);
create index if not exists ${name("incidents", "open_idx")} on ${incidents} (${i("tenant")}) where ${i("status")} <> 'resolved';
create index if not exists ${name("incidents", "commander_idx")} on ${incidents} (${i("tenant")}, ${i("commander")}) where ${i("commander")} is not null;
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
  ${u("createdAt")} timestamptz not null default now(),
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
);
create index if not exists ${name("impacts", "parent_idx")} on ${impacts} (${m("tenant")}, ${m("incident")});
create index if not exists ${name("impacts", "component_idx")} on ${impacts} (${m("tenant")}, ${m("component")});
${lockTable(impacts, { read: true })}
${readPolicy("impacts", m("tenant"))}

create table if not exists ${postmortems} (
  ${pm("id")} uuid primary key default gen_random_uuid(),
  ${pm("tenant")} ${ctx.idType} not null,
  ${pm("incident")} uuid not null unique,
  -- The only postmortem field a public incident's status page shows.
  ${pm("summary")} text check (${pm("summary")} is null or length(${pm("summary")}) <= 4000),
  ${pm("impact")} text check (${pm("impact")} is null or length(${pm("impact")}) <= 10000),
  ${pm("rootCause")} text check (${pm("rootCause")} is null or length(${pm("rootCause")}) <= 10000),
  ${pm("resolution")} text check (${pm("resolution")} is null or length(${pm("resolution")}) <= 10000),
  ${pm("actionItems")} jsonb not null default '[]'::jsonb check (jsonb_typeof(${pm("actionItems")}) = 'array'),
  ${pm("status")} text not null default 'draft' check (${pm("status")} in ('draft', 'published')),
  ${pm("publishedAt")} timestamptz,
  ${pm("author")} uuid,
  ${pm("createdAt")} timestamptz not null default now(),
  ${pm("updatedAt")} timestamptz not null default now(),
  foreign key (${pm("tenant")}, ${pm("incident")}) references ${incidents} (${i("tenant")}, ${i("id")}) on delete cascade
);
create index if not exists ${name("postmortems", "tenant_idx")} on ${postmortems} (${pm("tenant")}, ${pm("incident")});
${lockTable(postmortems, { read: true })}
${readPolicy("postmortems", pm("tenant"))}

-- One status page per organization. Anonymous visitors read it only through
-- public_status_page(slug), never through these tables.
create table if not exists ${pages} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${ctx.idType} not null unique,
  ${g("slug")} text not null unique check (${g("slug")} ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  ${g("title")} text not null check (length(${g("title")}) between 1 and 200),
  ${g("description")} text check (${g("description")} is null or length(${g("description")}) <= 2000),
  ${g("published")} boolean not null default false,
  ${g("createdAt")} timestamptz not null default now(),
  ${g("updatedAt")} timestamptz not null default now()
);
${lockTable(pages, { read: true })}
${readPolicy("pages", g("tenant"))}
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Incidents: severity, a status timeline, affected components, postmortems,
-- and a public status page read through one narrow function.
${tables(ctx)}${incidentsFunctions(ctx)}${statusPageFunctions(ctx)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
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
    {
      name: "set_incident_impacts",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_incident", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_incidents",
      args: ["{id}", "text", "text", "uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "save_postmortem", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "publish_postmortem", args: ["uuid"], returns: "jsonb" },
    {
      name: "save_status_page",
      args: ["{id}", "text", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "get_status_page", args: ["{id}"], returns: "jsonb" },
    {
      name: "public_status_page",
      args: ["text", "integer"],
      returns: "jsonb",
    },
  ];
}

export const INCIDENTS: ModuleDefinition = {
  internal: ["incident_apply_impacts", "incident_refresh_components"],
  name: "incidents",
  scopes: ["tenant"],
  title: "Incidents",
  description:
    "Incidents with a severity, a status timeline of updates, the components they affect and a postmortem, plus a public status page: component status, public incident updates and uptime history, readable anonymously through one function that returns only the fields marked public.",
  requires: ["tenant", "access"],
  integrates: ["notifications", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
