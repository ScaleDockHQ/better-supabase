import type { WorkflowEditorEvents } from "../../blocks/workflow-editor/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  fail,
  schemaPreamble,
  SERVICE_CALLER,
  writeExtraColumns,
} from "../shared.ts";
import { appUniqueIndex, asText, lockModuleTable } from "./over-app.ts";
import { builderPublisherSql } from "./workflow-editor-publisher.ts";
import {
  builderRuntimeSql,
  builderSql,
  definitionColumnsSql,
} from "./workflow-editor-sql.ts";
import {
  builderStartsSql,
  GRANT_ACTIONS,
  GRANT_PRINCIPALS,
  sqlList as list,
} from "./workflow-editor-starts.ts";

const EVENTS: BlockSqlEvents<WorkflowEditorEvents> = {
  "workflow.published": {
    subject: "workflows",
    payload: ["organizationId", "definitionId", "versionId", "version"],
  },
  "workflow_alert.triggered": {
    subject: "workflow-runs",
    payload: [
      "alertId",
      "organizationId",
      "definition",
      "onEvent",
      "channel",
      "runId",
      "status",
      "error",
    ],
    retries: true,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    definition: {
      table: "definitions",
      singular: "workflow_definition",
      primary: true,
    },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    definitions: {
      name: "workflow_definitions",
      app: {},
      lifecycle: { user: "createdBy", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        slug: "slug",
        name: "name",
        description: "description",
        subjectTypes: "subject_types",
        scope: "scope",
        forkedFrom: "forked_from",
        forkedFromVersion: "forked_from_version",
        restricted: "restricted",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["subjectTypes", "scope", "forkedFrom", "forkedFromVersion"],
      typed: ["scope"],
    },
    optOuts: {
      name: "workflow_opt_outs",
      app: {},
      lifecycle: { user: "createdBy", tenant: "tenant" },
      columns: {
        tenant: "tenant_id",
        definition: "definition_id",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    grants: {
      name: "workflow_definition_grants",
      app: {},
      lifecycle: { user: "createdBy" },
      columns: {
        id: "id",
        definition: "definition_id",
        principalKind: "principal_kind",
        principalId: "principal_id",
        action: "action",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      typed: ["principalKind", "action"],
    },
    versions: {
      name: "workflow_versions",
      app: {},
      columns: {
        id: "id",
        definition: "definition_id",
        version: "version",
        graph: "graph",
        compiled: "compiled",
        status: "status",
        createdBy: "created_by",
        createdAt: "created_at",
        publishedAt: "published_at",
        publishedBy: "published_by",
        owner: "owner_kind",
        permissions: "permissions",
        inputSchema: "input_schema",
      },
      typed: ["status", "owner"],
    },
    triggers: {
      name: "workflow_triggers",
      app: {},
      columns: {
        id: "id",
        definition: "definition_id",
        kind: "kind",
        config: "config",
        enabled: "enabled",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      typed: ["kind"],
    },
    webhookTokens: {
      name: "workflow_webhook_tokens",
      app: {},
      columns: {
        tokenHash: "token_hash",
        trigger: "trigger_id",
        createdAt: "created_at",
      },
    },
    credentials: {
      name: "workflow_credentials",
      app: {},
      lifecycle: { tenant: "tenant", credentials: ["ref"] },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        name: "name",
        ref: "credential_ref",
        scopes: "scopes",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    steps: {
      name: "workflow_step_library",
      app: {},
      columns: {
        name: "name",
        title: "title",
        description: "description",
        inputSchema: "input_schema",
        outputSchema: "output_schema",
        credentialKind: "credential_kind",
        operation: "operation",
        updatedAt: "updated_at",
      },
      optional: ["description"],
    },
    nodeRuns: {
      name: "workflow_node_runs",
      app: {},
      columns: {
        run: "run_id",
        node: "node_id",
        status: "status",
        attempts: "attempts",
        output: "output",
        error: "error",
        startedAt: "started_at",
        endedAt: "ended_at",
      },
      typed: ["status"],
    },
    alerts: {
      name: "workflow_alerts",
      app: {},
      columns: {
        id: "id",
        definition: "definition_id",
        onEvent: "on_event",
        threshold: "threshold",
        channel: "channel",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      typed: ["onEvent"],
    },
    alertFires: {
      name: "workflow_alert_fires",
      app: {},
      columns: { alert: "alert_id", run: "run_id", firedAt: "fired_at" },
    },
  },
};

const WORKFLOW_NODE_KINDS = [
  "trigger",
  "step",
  "sleep",
  "approval",
  "condition",
] as const;

const WORKFLOW_TRIGGER_KINDS = [
  "manual",
  "webhook",
  "schedule",
  "form",
  "chat",
] as const;

const NODE_RUN_STATUSES = [
  "running",
  "waiting",
  "completed",
  "failed",
  "skipped",
] as const;

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const s = builderSql(ctx, layout.accessProvider?.operations);

  const {
    id,
    fn,
    d,
    v,
    t,
    w,
    c,
    l,
    n,
    a,
    f,
    o,
    g,
    cd,
    cv,
    ct,
    cw,
    cc,
    cl,
    cn,
    ca,
    cf,
    co,
    cg,
    r,
    cr,
    allowed,
    granted,
    optedOut,
    holds,
    forbidden,
    callable,
    readable,
    definitionReadable,
    definitionJson,
    versionJson,
    draftColumn,
    draftValue,
    scoped,
    forked,
    subjectTyped,
  } = s;

  const extras = ctx.extraColumns("definitions", ["fields"]);
  const extra = extraFieldsArg(extras);

  return `${schemaPreamble(ctx)}
create extension if not exists pgcrypto with schema extensions;

-- Workflow definitions a tenant builds, by slug. Each has numbered versions:
-- at most one draft that the editor saves, at most one published version
-- that runs start from, and archived ones.
create table if not exists ${d} (
  ${cd("id")} uuid primary key default gen_random_uuid(),
  ${cd("tenant")} ${id},
  ${cd("slug")} text not null check (${cd("slug")} ~ '^[a-z0-9][a-z0-9-]{0,99}$'),
  ${cd("name")} text not null check (length(${cd("name")}) between 1 and 200),
  ${cd("description")} text check (length(${cd("description")}) <= 2000),
  ${cd("createdBy")} uuid references auth.users (id) on delete set null,
  ${cd("createdAt")} timestamptz not null default now(),
  ${cd("updatedAt")} timestamptz not null default now(),
  constraint ${ctx.naming.rename("workflow_definitions_tenant_slug_key")} unique nulls not distinct (${cd("tenant")}, ${cd("slug")})
);
create index if not exists ${ctx.naming.rename("workflow_definitions_created_by_idx")} on ${d} (${cd("createdBy")});
-- subject_types: the record types a run of the definition may belong to.
-- scope: a system definition has no tenant, every member with
-- workflow.read reads it, only the service role saves and publishes it, and
-- it runs in a tenant until the tenant opts out (workflow_opt_outs).
-- forked_from: the definition and version a fork copied.
-- restricted: running or editing it also needs a workflow_definition_grants
-- row (or workflow.admin).
${definitionColumnsSql(ctx, s)}${addExtraColumns(d, extras)}
${lockModuleTable(ctx, "definitions", { read: true })}
${renderPolicy(makePolicy({ table: d, name: ctx.naming.rename("workflow_definitions_read"), command: "select", roles: ["authenticated"], using: scoped ? `${readable(cd("tenant"))} or (${cd("scope")} = 'system' and exists (select ${ctx.scope.ids(s.permission("read"))}))` : readable(cd("tenant")) }), { drop: true, target: d })}

-- The tenants that opted out of a definition, usually a system one: its
-- triggers and starts skip them (WORKFLOW_OPTED_OUT).
create table if not exists ${o} (
  ${co("tenant")} ${id} not null,
  ${co("definition")} uuid not null references ${d} (${cd("id")}) on delete cascade,
  ${co("createdBy")} uuid references auth.users (id) on delete set null,
  ${co("createdAt")} timestamptz not null default now(),
  primary key (${co("tenant")}, ${co("definition")})
);${appUniqueIndex(ctx, "optOuts", ["tenant", "definition"])}
create index if not exists workflow_opt_outs_definition_idx on ${o} (${co("definition")});
create index if not exists workflow_opt_outs_created_by_idx on ${o} (${co("createdBy")});
${lockModuleTable(ctx, "optOuts", { read: true })}
${renderPolicy(makePolicy({ table: o, name: "workflow_opt_outs_read", command: "select", roles: ["authenticated"], using: readable(co("tenant")) }), { drop: true, target: o })}

-- Who may run or edit a restricted definition: a user, a team or an
-- organization role. An edit grant also runs it.
create table if not exists ${g} (
  ${cg("id")} uuid primary key default gen_random_uuid(),
  ${cg("definition")} uuid not null references ${d} (${cd("id")}) on delete cascade,
  ${cg("principalKind")} text not null check (${cg("principalKind")} in (${list(GRANT_PRINCIPALS)})),
  ${cg("principalId")} text not null check (length(${cg("principalId")}) between 1 and 200),
  ${cg("action")} text not null check (${cg("action")} in (${list(GRANT_ACTIONS)})),
  ${cg("createdBy")} uuid references auth.users (id) on delete set null,
  ${cg("createdAt")} timestamptz not null default now(),
  constraint ${ctx.naming.rename("workflow_definition_grants_key")} unique (${cg("definition")}, ${cg("principalKind")}, ${cg("principalId")}, ${cg("action")})
);${appUniqueIndex(ctx, "grants", ["definition", "principalKind", "principalId", "action"])}
create index if not exists ${ctx.naming.rename("workflow_definition_grants_principal_idx")} on ${g} (${cg("principalKind")}, ${cg("principalId")});
create index if not exists ${ctx.naming.rename("workflow_definition_grants_created_by_idx")} on ${g} (${cg("createdBy")});
${lockModuleTable(ctx, "grants", { read: true })}
${renderPolicy(makePolicy({ table: g, name: ctx.naming.rename("workflow_definition_grants_read"), command: "select", roles: ["authenticated"], using: definitionReadable(cg("definition")) }), { drop: true, target: g })}

create table if not exists ${v} (
  ${cv("id")} uuid primary key default gen_random_uuid(),
  ${cv("definition")} uuid not null references ${d} (${cd("id")}) on delete cascade,
  ${cv("version")} integer not null check (${cv("version")} > 0),
  ${cv("graph")} jsonb not null default '{"nodes": [], "edges": []}'::jsonb,
  ${cv("compiled")} jsonb,
  ${cv("status")} text not null default 'draft' check (${cv("status")} in ('draft', 'published', 'archived')),
  ${cv("createdBy")} uuid references auth.users (id) on delete set null,
  ${cv("createdAt")} timestamptz not null default now(),
  ${cv("publishedAt")} timestamptz,
  constraint workflow_versions_definition_version_key unique (${cv("definition")}, ${cv("version")})
);
-- Who published a version and with which rights: its steps run as that
-- user, narrowed to permissions, or as the app's service principal when an
-- organization owns it (published by the service role). A deleted user
-- leaves published_by null with owner_kind 'user', so the steps fail.
alter table ${v} add column if not exists ${cv("publishedBy")} uuid references auth.users (id) on delete set null;
alter table ${v} add column if not exists ${cv("owner")} text check (${cv("owner")} in ('user', 'organization'));
alter table ${v} add column if not exists ${cv("permissions")} text[] not null default '{}';
-- input_schema: the JSON Schema of the input a run of the version takes, as
-- the editor saved it; callers such as template attachments check against it.
alter table ${v} add column if not exists ${cv("inputSchema")} jsonb
  check (${cv("inputSchema")} is null or jsonb_typeof(${cv("inputSchema")}) = 'object');
create index if not exists workflow_versions_published_by_idx on ${v} (${cv("publishedBy")});
create unique index if not exists workflow_versions_one_draft_idx on ${v} (${cv("definition")}) where ${cv("status")} = 'draft';
create unique index if not exists workflow_versions_one_published_idx on ${v} (${cv("definition")}) where ${cv("status")} = 'published';
create index if not exists workflow_versions_created_by_idx on ${v} (${cv("createdBy")});
${lockModuleTable(ctx, "versions", { read: true })}
${renderPolicy(makePolicy({ table: v, name: "workflow_versions_read", command: "select", roles: ["authenticated"], using: definitionReadable(cv("definition")) }), { drop: true, target: v })}

-- How runs of a definition start. A webhook trigger's token is stored as its
-- SHA-256 only; schedule, form and chat triggers keep their settings
-- in config for the app to bind.
create table if not exists ${t} (
  ${ct("id")} uuid primary key default gen_random_uuid(),
  ${ct("definition")} uuid not null references ${d} (${cd("id")}) on delete cascade,
  ${ct("kind")} text not null check (${ct("kind")} in (${list(WORKFLOW_TRIGGER_KINDS)})),
  ${ct("config")} jsonb not null default '{}'::jsonb,
  ${ct("enabled")} boolean not null default true,
  ${ct("createdAt")} timestamptz not null default now(),
  ${ct("updatedAt")} timestamptz not null default now()
);
create index if not exists workflow_triggers_definition_idx on ${t} (${ct("definition")});${s.tableExtras.triggers}
${lockModuleTable(ctx, "triggers", { read: true })}
${renderPolicy(makePolicy({ table: t, name: "workflow_triggers_read", command: "select", roles: ["authenticated"], using: definitionReadable(ct("definition")) }), { drop: true, target: t })}

create table if not exists ${w} (
  ${cw("tokenHash")} bytea primary key,
  ${cw("trigger")} uuid not null unique references ${t} (${ct("id")}) on delete cascade,
  ${cw("createdAt")} timestamptz not null default now()
);
${lockModuleTable(ctx, "webhookTokens")}

-- Credentials the steps of a tenant's workflows use. A row names the secret
-- with a credential_ref that a CredentialProvider resolves; it never holds
-- the secret, so graphs and run state never see a token.
create table if not exists ${c} (
  ${cc("id")} uuid primary key default gen_random_uuid(),
  ${cc("tenant")} ${id},
  ${cc("kind")} text not null check (length(${cc("kind")}) between 1 and 100),
  ${cc("name")} text not null check (length(${cc("name")}) between 1 and 200),
  ${cc("ref")} jsonb not null check (jsonb_typeof(${cc("ref")} -> 'provider') = 'string'),
  ${cc("scopes")} text[] not null default '{}',
  ${cc("createdBy")} uuid references auth.users (id) on delete set null,
  ${cc("createdAt")} timestamptz not null default now(),
  constraint workflow_credentials_tenant_name_key unique nulls not distinct (${cc("tenant")}, ${cc("name")})
);${s.tableExtras.credentials}
create index if not exists workflow_credentials_created_by_idx on ${c} (${cc("createdBy")});
${lockModuleTable(ctx, "credentials", { read: true })}
${renderPolicy(makePolicy({ table: c, name: "workflow_credentials_read", command: "select", roles: ["authenticated"], using: readable(cc("tenant")) }), { drop: true, target: c })}

-- The steps the deployment provides, synced from code: the palette of the
-- builder and the names a published graph may use.
create table if not exists ${l} (
  ${cl("name")} text primary key check (${cl("name")} ~ '^[A-Za-z][A-Za-z0-9_.-]{0,99}$'),
  ${cl("title")} text not null check (length(${cl("title")}) between 1 and 200),${
    ctx.has("steps", "description")
      ? `
  ${cl("description")} text,`
      : ""
  }
  ${cl("inputSchema")} jsonb not null default '{}'::jsonb,
  ${cl("outputSchema")} jsonb not null default '{}'::jsonb,
  ${cl("credentialKind")} text,
  ${cl("updatedAt")} timestamptz not null default now()
);${appUniqueIndex(ctx, "steps", ["name"])}
alter table ${l} add column if not exists ${cl("operation")} text
  check (length(${cl("operation")}) between 1 and 200);
${lockModuleTable(ctx, "steps", { read: true })}
${renderPolicy(makePolicy({ table: l, name: "workflow_step_library_read", command: "select", roles: ["authenticated"], using: "true" }), { drop: true, target: l })}

-- The status of each node of a run, by node id, written by the engine.
create table if not exists ${n} (
  ${cn("run")} uuid not null references ${r} (${cr("id")}) on delete cascade,
  ${cn("node")} text not null check (length(${cn("node")}) between 1 and 100),
  ${cn("status")} text not null check (${cn("status")} in (${list(NODE_RUN_STATUSES)})),
  ${cn("attempts")} integer not null default 0,
  ${cn("output")} jsonb,
  ${cn("error")} text,
  ${cn("startedAt")} timestamptz,
  ${cn("endedAt")} timestamptz,
  primary key (${cn("run")}, ${cn("node")})
);${appUniqueIndex(ctx, "nodeRuns", ["run", "node"])}
${lockModuleTable(ctx, "nodeRuns", { read: true })}
${renderPolicy(makePolicy({ table: n, name: "workflow_node_runs_read", command: "select", roles: ["authenticated"], using: `${cn("run")} in (select x.${cr("id")} from ${r} x)` }), { drop: true, target: n })}

-- Alerts on a definition's runs: failed fires when a run fails, slow when a
-- run is still unfinished after threshold (check_workflow_alerts). Each
-- fires once per run and writes a workflow_alert.triggered outbox event.
create table if not exists ${a} (
  ${ca("id")} uuid primary key default gen_random_uuid(),
  ${ca("definition")} uuid not null references ${d} (${cd("id")}) on delete cascade,
  ${ca("onEvent")} text not null check (${ca("onEvent")} in ('failed', 'slow')),
  ${ca("threshold")} interval,
  ${ca("channel")} jsonb not null default '{}'::jsonb,
  ${ca("createdBy")} uuid references auth.users (id) on delete set null,
  ${ca("createdAt")} timestamptz not null default now(),
  constraint workflow_alerts_threshold_check check (${ca("onEvent")} <> 'slow' or ${ca("threshold")} > interval '0')
);
create index if not exists workflow_alerts_definition_idx on ${a} (${ca("definition")});
create index if not exists workflow_alerts_created_by_idx on ${a} (${ca("createdBy")});
${lockModuleTable(ctx, "alerts", { read: true })}
${renderPolicy(makePolicy({ table: a, name: "workflow_alerts_read", command: "select", roles: ["authenticated"], using: definitionReadable(ca("definition")) }), { drop: true, target: a })}

create table if not exists ${f} (
  ${cf("alert")} uuid not null references ${a} (${ca("id")}) on delete cascade,
  ${cf("run")} uuid not null references ${r} (${cr("id")}) on delete cascade,
  ${cf("firedAt")} timestamptz not null default now(),
  primary key (${cf("alert")}, ${cf("run")})
);${appUniqueIndex(ctx, "alertFires", ["alert", "run"])}
create index if not exists workflow_alert_fires_run_idx on ${f} (${cf("run")});
${lockModuleTable(ctx, "alertFires")}

-- Problems that keep a graph from being published, as messages; empty when
-- it may be. The step names must be in the step library.
create or replace function ${fn("validate_workflow_graph")}(graph jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_errors text[] := '{}';
  v_nodes jsonb := coalesce(graph -> 'nodes', 'null'::jsonb);
  v_edges jsonb := coalesce(graph -> 'edges', '[]'::jsonb);
  v_node jsonb;
  v_edge jsonb;
  v_ids text[] := '{}';
  v_triggers integer := 0;
begin
  if jsonb_typeof(v_nodes) <> 'array' or jsonb_typeof(v_edges) <> 'array' then
    return jsonb_build_array('A graph has a nodes array and an edges array');
  end if;
  for v_node in select value from jsonb_array_elements(v_nodes) loop
    if coalesce(jsonb_typeof(v_node -> 'id'), '') <> 'string' or (v_node ->> 'id') !~ '^[A-Za-z0-9_-]{1,100}$' then
      v_errors := array_append(v_errors, 'Every node has an id of 1 to 100 letters, digits, underscores or hyphens');
      continue;
    end if;
    if (v_node ->> 'id') = any (v_ids) then
      v_errors := array_append(v_errors, format('Node %s appears twice', v_node ->> 'id'));
    end if;
    v_ids := array_append(v_ids, v_node ->> 'id');
    if coalesce(v_node ->> 'kind', '') not in (${list(WORKFLOW_NODE_KINDS)}) then
      v_errors := array_append(v_errors, format('Node %s has an unknown kind', v_node ->> 'id'));
    elsif v_node ->> 'kind' = 'trigger' then
      v_triggers := v_triggers + 1;
    elsif v_node ->> 'kind' = 'step' and not exists (
      select 1 from ${l} s where s.${cl("name")} = v_node ->> 'step'
    ) then
      v_errors := array_append(v_errors, format('Node %s uses step %s, which is not in the step library', v_node ->> 'id', coalesce(v_node ->> 'step', 'null')));
    end if;
  end loop;
  if v_triggers < 1 then
    v_errors := array_append(v_errors, 'A graph has at least one trigger node');
  end if;
  for v_edge in select value from jsonb_array_elements(v_edges) loop
    if not coalesce((v_edge ->> 'source') = any (v_ids), false) or not coalesce((v_edge ->> 'target') = any (v_ids), false) then
      v_errors := array_append(v_errors, format('Edge %s joins a node that does not exist', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$$;
${callable(`${fn("validate_workflow_graph")}(jsonb)`)}

-- Creates a definition, or renames the one with the same tenant and slug:
-- the service role or workflow.edit in tenant (and an edit grant on a
-- restricted one). subject_types and restricted keep their value when null;
-- only workflow.admin changes restricted. A system definition (scope
-- 'system') has no tenant and only the service role saves it; the scope of
-- a saved definition never changes.
drop function if exists ${fn("save_workflow_definition")}(${id}, text, text, text);
-- fields: the extra columns (blocks["workflow-editor"].options.extraColumns) to set.
${extra.drop(fn("save_workflow_definition"), `${id}, text, text, text, text[], text, boolean`)}
create or replace function ${fn("save_workflow_definition")}(
  tenant ${id},
  slug text,
  name text,
  description text default null,
  subject_types text[] default null,
  scope text default null,
  restricted boolean default null${extra.param}
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${d}%rowtype;
  v_scope text := coalesce(scope, 'tenant');
begin
  if v_scope not in ('tenant', 'system') then
    ${fail("WORKFLOW_SCOPE_INVALID", "scope is tenant or system", "22023")}
  end if;
  if v_scope = 'system' and tenant is not null then
    ${fail("WORKFLOW_SCOPE_INVALID", "A system workflow has no tenant", "22023")}
  end if;
  if v_scope = 'system' and not (${SERVICE_CALLER}) then
    ${forbidden("Only the service role saves a system workflow")}
  end if;${
    scoped
      ? ""
      : `
  if v_scope = 'system' then
    ${fail("WORKFLOW_SCOPE_UNSUPPORTED", "this workflow definitions table has no scope column, so there are no system workflows", "22023")}
  end if;`
  }${
    subjectTyped
      ? ""
      : `
  if cardinality(coalesce(subject_types, '{}')) > 0 then
    ${fail("WORKFLOW_SUBJECT_UNSUPPORTED", "this workflow definitions table has no subject types column", "22023")}
  end if;`
  }
  if not ${allowed("tenant", "edit")} then
    ${forbidden("You may not edit workflows here")}
  end if;
  select * into v_row from ${d} x
  where x.${cd("tenant")} is not distinct from tenant and x.${cd("slug")} = slug
  for update;
  if found then${
    scoped
      ? `
    if scope is not null and scope <> ${asText(ctx, "definitions", `v_row.${cd("scope")}`)} then
      ${fail("WORKFLOW_SCOPE_FIXED", "A workflow's scope never changes", "22023")}
    end if;`
      : ""
  }
    if not ${granted(`v_row.${cd("id")}`, "tenant", "edit")} then
      ${forbidden("You may not edit this workflow")}
    end if;
    if restricted is not null and restricted <> v_row.${cd("restricted")} and not ${allowed("tenant", "admin")} then
      ${forbidden("Only a workflow admin restricts a workflow")}
    end if;
    update ${d} x set
      ${cd("name")} = name,
      ${cd("description")} = description,${subjectTyped ? `\n      ${cd("subjectTypes")} = coalesce(subject_types, x.${cd("subjectTypes")}),` : ""}
      ${cd("restricted")} = coalesce(restricted, x.${cd("restricted")}),
      ${cd("updatedAt")} = now()
    where x.${cd("id")} = v_row.${cd("id")}
    returning * into v_row;
  else
    if coalesce(restricted, false) and not ${allowed("tenant", "admin")} then
      ${forbidden("Only a workflow admin restricts a workflow")}
    end if;
    insert into ${d} (${cd("tenant")}, ${cd("slug")}, ${cd("name")}, ${cd("description")}${subjectTyped ? `, ${cd("subjectTypes")}` : ""}${scoped ? `, ${cd("scope")}` : ""}, ${cd("restricted")}, ${cd("createdBy")})
    values (tenant, slug, name, description${subjectTyped ? ", coalesce(subject_types, '{}')" : ""}${scoped ? `, ${ctx.cast("definitions", "scope", "v_scope")}` : ""}, coalesce(restricted, false), (select auth.uid()))
    returning * into v_row;
  end if;${writeExtraColumns(d, extras, "save_workflow_definition.fields", `x.${cd("id")} = v_row.${cd("id")}`, "v_row")}
  return ${definitionJson("v_row")};
end;
$$;
${callable(`${fn("save_workflow_definition")}(${id}, text, text, text, text[], text, boolean${extra.type})`)}

-- The definitions the caller may read, by name, each with the number of its
-- published version and whether it has a draft. With tenant, the tenant's
-- definitions and the system ones, each with optedOut; with subject_type,
-- only the definitions that run on it. A fork has upstreamVersion (its
-- source's published version) and behind (whether that is newer than the
-- version it copied).
drop function if exists ${fn("workflow_definitions_list")}(${id});
create or replace function ${fn("workflow_definitions_list")}(tenant ${id} default null, subject_type text default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    ${definitionJson("x")} || jsonb_build_object(
      'published', (select y.${cv("version")} from ${v} y where y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'published'),
      'draft', exists (select 1 from ${v} y where y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'draft'),
      'upstreamVersion', ${forked ? "u.version" : "null"},
      'behind', ${forked ? `coalesce(u.version > x.${cd("forkedFromVersion")}, false)` : "false"},
      'optedOut', case when workflow_definitions_list.tenant is null then null else ${optedOut(`x.${cd("id")}`, "workflow_definitions_list.tenant")} end
    ) order by x.${cd("name")}), '[]'::jsonb)
  from ${d} x${
    forked
      ? `
  left join lateral (
    select y.${cv("version")} as version from ${v} y
    where y.${cv("definition")} = x.${cd("forkedFrom")} and y.${cv("status")} = 'published'
  ) u on true`
      : ""
  }
  where (workflow_definitions_list.tenant is null
      or x.${cd("tenant")} = workflow_definitions_list.tenant${
        scoped
          ? `
      or x.${cd("scope")} = 'system')`
          : ")"
      }
    and ${
      subjectTyped
        ? `(workflow_definitions_list.subject_type is null
      or workflow_definitions_list.subject_type = any (x.${cd("subjectTypes")}))`
        : "workflow_definitions_list.subject_type is null"
    };
$$;
${callable(`${fn("workflow_definitions_list")}(${id}, text)`)}

create or replace function ${fn("workflow_definition_get")}(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${definitionJson("x")} from ${d} x where x.${cd("id")} = workflow_definition_get.definition;
$$;
${callable(`${fn("workflow_definition_get")}(uuid)`)}

-- Deletes a definition with its versions, triggers and alerts: the service
-- role or workflow.admin in its tenant. Its runs stay.
create or replace function ${fn("remove_workflow_definition")}(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${d} x
  where x.${cd("id")} = definition and ${allowed(`x.${cd("tenant")}`, "admin")};
  return found;
end;
$$;
${callable(`${fn("remove_workflow_definition")}(uuid)`)}

-- Saves graph as the definition's draft: updates the draft, or opens one
-- numbered after the last version. workflow.edit in its tenant, and an edit
-- grant on a restricted definition. A null input_schema keeps the draft's
-- current one.
drop function if exists ${fn("save_workflow_draft")}(uuid, jsonb);
create or replace function ${fn("save_workflow_draft")}(definition uuid, graph jsonb, input_schema jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${id};
  v_row ${v}%rowtype;
begin
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = definition for update;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  if not (${allowed("v_tenant", "edit")} and ${granted("definition", "v_tenant", "edit")}) then
    ${forbidden("You may not edit this workflow")}
  end if;
  if jsonb_typeof(graph) <> 'object' then
    ${fail("WORKFLOW_GRAPH_INVALID", "A graph is an object", "22023")}
  end if;
  if input_schema is not null and jsonb_typeof(input_schema) <> 'object' then
    ${fail("WORKFLOW_GRAPH_INVALID", "An input schema is an object", "22023")}
  end if;
  update ${v} x set ${cv("graph")} = graph, ${cv("compiled")} = null,
    ${cv("inputSchema")} = coalesce(input_schema, x.${cv("inputSchema")})
  where x.${cv("definition")} = definition and x.${cv("status")} = 'draft'
  returning * into v_row;
  if not found then
    insert into ${v} (${cv("definition")}, ${cv("version")}, ${cv("graph")}, ${cv("inputSchema")}, ${cv("createdBy")}${draftColumn})
    values (
      definition,
      coalesce((select max(y.${cv("version")}) from ${v} y where y.${cv("definition")} = definition), 0) + 1,
      graph,
      coalesce(input_schema, (select y.${cv("inputSchema")} from ${v} y
        where y.${cv("definition")} = definition order by y.${cv("version")} desc limit 1)),
      (select auth.uid())${draftValue}
    )
    returning * into v_row;
  end if;
  update ${d} x set ${cd("updatedAt")} = now() where x.${cd("id")} = definition;
  return ${versionJson("v_row", true)};
end;
$$;
${callable(`${fn("save_workflow_draft")}(uuid, jsonb, jsonb)`)}

${builderPublisherSql(s)}

-- Publishes a version: workflow.publish in its tenant (and an edit grant on
-- a restricted definition; a system one only the service role), a graph
-- validate_workflow_graph accepts, and every permission its steps need
-- (workflow_graph_permissions), which are stored with the publisher. The
-- service role publishes for the organization. The version published
-- before is archived. Only the service role may store the engine's
-- compiled form, also on a version that is already published.
create or replace function ${fn("publish_workflow_version")}(version uuid, compiled jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${v}%rowtype;
  v_tenant ${id};
  v_errors jsonb;
  v_permissions text[];
  v_missing text[];
  v_service boolean := ${SERVICE_CALLER};
begin
  select * into v_row from ${v} x where x.${cv("id")} = version for update;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow version", "P0002")}
  end if;
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = v_row.${cv("definition")};
  if not (${allowed("v_tenant", "publish")} and ${granted(`v_row.${cv("definition")}`, "v_tenant", "edit")}) then
    ${forbidden("You may not publish this workflow")}
  end if;
  if compiled is not null and not (${SERVICE_CALLER}) then
    ${fail("WORKFLOW_COMPILED_FORBIDDEN", "Only the service role may store a compiled form")}
  end if;
  if v_row.${cv("status")} = 'published' then
    if compiled is not null then
      update ${v} x set ${cv("compiled")} = compiled
      where x.${cv("id")} = v_row.${cv("id")}
      returning * into v_row;
    end if;
    return ${versionJson("v_row", true)};
  end if;
  v_errors := ${fn("validate_workflow_graph")}(v_row.${cv("graph")});
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  v_permissions := ${fn("workflow_graph_permissions")}(v_row.${cv("graph")});
  if not v_service then
    select array_agg(p order by p) into v_missing
    from unnest(v_permissions) p
    where not ${holds("v_tenant", "p")};
    if v_missing is not null then
      raise exception 'You may not publish a workflow whose steps need %', array_to_string(v_missing, ', ')
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_FORBIDDEN',
          detail = jsonb_build_object('permissions', to_jsonb(v_missing))::text;
    end if;
  end if;
  update ${v} x set ${cv("status")} = ${ctx.cast("versions", "status", "'archived'")}
  where x.${cv("definition")} = v_row.${cv("definition")} and x.${cv("status")} = 'published';
  update ${v} x set
    ${cv("status")} = ${ctx.cast("versions", "status", "'published'")},
    ${cv("compiled")} = compiled,
    ${cv("publishedAt")} = now(),
    ${cv("publishedBy")} = case when v_service then null else (select auth.uid()) end,
    ${cv("owner")} = ${ctx.cast("versions", "owner", "case when v_service then 'organization' else 'user' end")},
    ${cv("permissions")} = v_permissions
  where x.${cv("id")} = v_row.${cv("id")}
  returning * into v_row;
  ${ctx.record({
    type: "workflow.published",
    payload: `jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row.${cv("definition")}, 'versionId', v_row.${cv("id")}, 'version', v_row.${cv("version")})`,
    subject: `'workflows/' || v_row.${cv("definition")}::text`,
    tenant: "v_tenant",
    key: `'workflow.published:' || v_row.${cv("id")}::text`,
    audit: {
      category: "configuration",
      targetType: "workflow_version",
      recordId: `v_row.${cv("id")}::text`,
    },
  })}
  return ${versionJson("v_row", true)};
end;
$$;
${callable(`${fn("publish_workflow_version")}(uuid, jsonb)`)}

-- A definition's versions, newest first, without their graphs.
create or replace function ${fn("workflow_versions_list")}(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${versionJson("x", false)} order by x.${cv("version")} desc), '[]'::jsonb)
  from ${v} x where x.${cv("definition")} = workflow_versions_list.definition;
$$;
${callable(`${fn("workflow_versions_list")}(uuid)`)}

create or replace function ${fn("workflow_version_get")}(version uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${versionJson("x", true)} from ${v} x where x.${cv("id")} = workflow_version_get.version;
$$;
${callable(`${fn("workflow_version_get")}(uuid)`)}

${builderStartsSql(ctx, s)}

${builderRuntimeSql(s)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("definitions", ["fields"]),
  ).contract;

  return [
    { name: "validate_workflow_graph", args: ["jsonb"], returns: "jsonb" },
    {
      name: "save_workflow_definition",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text[]",
        "text",
        "boolean",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "workflow_definitions_list",
      args: ["{id}", "text"],
      returns: "jsonb",
    },
    { name: "workflow_definition_get", args: ["uuid"], returns: "jsonb" },
    { name: "remove_workflow_definition", args: ["uuid"], returns: "boolean" },
    {
      name: "save_workflow_draft",
      args: ["uuid", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "publish_workflow_version",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "workflow_versions_list", args: ["uuid"], returns: "jsonb" },
    { name: "workflow_version_get", args: ["uuid"], returns: "jsonb" },
    { name: "workflow_start_target", args: ["uuid", "{id}"], returns: "jsonb" },
    {
      name: "workflow_subject_start_target",
      args: ["uuid", "text", "text", "{id}"],
      returns: "jsonb",
    },
    {
      name: "start_test_run",
      args: ["uuid", "uuid", "text", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "fork_workflow_definition",
      args: ["uuid", "{id}", "text"],
      returns: "jsonb",
    },
    {
      name: "set_workflow_opt_out",
      args: ["{id}", "uuid", "boolean"],
      returns: "boolean",
    },
    {
      name: "set_workflow_definition_grant",
      args: ["uuid", "text", "text", "text", "boolean"],
      returns: "boolean",
    },
    {
      name: "workflow_definition_grants_list",
      args: ["uuid"],
      returns: "jsonb",
    },
    { name: "workflow_graph_permissions", args: ["jsonb"], returns: "text[]" },
    {
      name: "workflow_run_principal",
      args: ["uuid", "{id}"],
      returns: "jsonb",
    },
    {
      name: "save_workflow_trigger",
      args: ["uuid", "text", "jsonb", "boolean", "uuid"],
      returns: "jsonb",
    },
    { name: "workflow_triggers_list", args: ["uuid"], returns: "jsonb" },
    { name: "remove_workflow_trigger", args: ["uuid"], returns: "boolean" },
    { name: "rotate_workflow_webhook_token", args: ["uuid"], returns: "text" },
    { name: "workflow_webhook_target", args: ["text"], returns: "jsonb" },
    {
      name: "save_workflow_credential",
      args: ["{id}", "text", "text", "jsonb", "text[]"],
      returns: "jsonb",
    },
    { name: "workflow_credentials_list", args: ["{id}"], returns: "jsonb" },
    { name: "workflow_credential_get", args: ["uuid"], returns: "jsonb" },
    { name: "remove_workflow_credential", args: ["uuid"], returns: "jsonb" },
    { name: "sync_workflow_steps", args: ["jsonb"], returns: "integer" },
    { name: "workflow_steps_list", args: [], returns: "jsonb" },
    {
      name: "record_workflow_node_run",
      args: ["text", "text", "text", "integer", "jsonb", "text"],
      returns: "boolean",
    },
    { name: "workflow_node_runs_list", args: ["text"], returns: "jsonb" },
    {
      name: "save_workflow_alert",
      args: ["uuid", "text", "jsonb", "interval", "uuid"],
      returns: "jsonb",
    },
    { name: "workflow_alerts_list", args: ["uuid"], returns: "jsonb" },
    { name: "remove_workflow_alert", args: ["uuid"], returns: "boolean" },
    { name: "check_workflow_alerts", args: ["integer"], returns: "integer" },
  ];
}

export const WORKFLOW_BUILDER: BlockSqlDefinition = {
  name: "workflow-editor",
  scopes: ["tenant"],
  title: "Workflow builder",
  description:
    "Workflow definitions a tenant edits as an engine-neutral node graph, with draft, published and archived versions, triggers (webhook tokens stored hashed), credential references a CredentialProvider resolves, a synced step library, per-node run status pinged on the run's topic, and failed and slow alerts written as workflow_alert.triggered outbox events.",
  requires: ["workflows", "memberships", "permissions"],
  integrates: ["service-accounts", "subjects", "teams"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "Definitions gain subject_types, scope, forked_from, forked_from_version and restricted, versions gain input_schema; workflow_opt_outs and workflow_definition_grants are new; save_workflow_definition, save_workflow_draft, workflow_definitions_list, workflow_start_target and workflow_run_principal take the new arguments, and fork_workflow_definition, set_workflow_opt_out, set_workflow_definition_grant, start_test_run and workflow_subject_start_target are new.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "Event triggers go: an automation with a workflow action starts a definition on an outbox event. Triggers of kind event are deleted and workflow_event_targets is dropped.",
      sql: (ctx) =>
        ctx.manages
          ? `${ctx.owns("triggers") ? `delete from ${ctx.table("triggers")} where ${ctx.col("triggers", "kind")} = 'event';\n` : ""}drop function if exists ${ctx.fn("workflow_event_targets")}(text, ${ctx.idType});`
          : "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
