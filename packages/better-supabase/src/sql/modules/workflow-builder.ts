import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";
import { builderRuntimeSql, builderSql } from "./workflow-builder-sql.ts";

const NAMES: ModuleNames = {
  tables: {
    definitions: {
      name: "workflow_definitions",
      lifecycle: { user: "createdBy", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "tenant_id",
        slug: "slug",
        name: "name",
        description: "description",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    versions: {
      name: "workflow_versions",
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
      },
    },
    triggers: {
      name: "workflow_triggers",
      columns: {
        id: "id",
        definition: "definition_id",
        kind: "kind",
        config: "config",
        enabled: "enabled",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    webhookTokens: {
      name: "workflow_webhook_tokens",
      columns: {
        tokenHash: "token_hash",
        trigger: "trigger_id",
        createdAt: "created_at",
      },
    },
    credentials: {
      name: "workflow_credentials",
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
      columns: {
        name: "name",
        title: "title",
        description: "description",
        inputSchema: "input_schema",
        outputSchema: "output_schema",
        credentialKind: "credential_kind",
        updatedAt: "updated_at",
      },
    },
    nodeRuns: {
      name: "workflow_node_runs",
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
    },
    alerts: {
      name: "workflow_alerts",
      columns: {
        id: "id",
        definition: "definition_id",
        onEvent: "on_event",
        threshold: "threshold",
        channel: "channel",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    alertFires: {
      name: "workflow_alert_fires",
      columns: {
        alert: "alert_id",
        run: "run_id",
        firedAt: "fired_at",
      },
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
  "event",
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

const list = (values: readonly string[]): string =>
  values.map(sqlString).join(", ");

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const s = builderSql(ctx);
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
    cd,
    cv,
    ct,
    cw,
    cc,
    cl,
    cn,
    ca,
    cf,
    r,
    cr,
    allowed,
    forbidden,
    callable,
    readable,
    definitionReadable,
    definitionJson,
    versionJson,
  } = s;

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
  constraint workflow_definitions_tenant_slug_key unique nulls not distinct (${cd("tenant")}, ${cd("slug")})
);
create index if not exists workflow_definitions_created_by_idx on ${d} (${cd("createdBy")});
alter table ${d} enable row level security;
revoke all on ${d} from anon, authenticated;
grant select on ${d} to authenticated;
grant all on ${d} to service_role;
drop policy if exists workflow_definitions_read on ${d};
create policy workflow_definitions_read on ${d} for select to authenticated
  using (${readable(cd("tenant"))});

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
create unique index if not exists workflow_versions_one_draft_idx on ${v} (${cv("definition")}) where ${cv("status")} = 'draft';
create unique index if not exists workflow_versions_one_published_idx on ${v} (${cv("definition")}) where ${cv("status")} = 'published';
create index if not exists workflow_versions_created_by_idx on ${v} (${cv("createdBy")});
alter table ${v} enable row level security;
revoke all on ${v} from anon, authenticated;
grant select on ${v} to authenticated;
grant all on ${v} to service_role;
drop policy if exists workflow_versions_read on ${v};
create policy workflow_versions_read on ${v} for select to authenticated
  using (${definitionReadable(cv("definition"))});

-- How runs of a definition start. A webhook trigger's token is stored as its
-- SHA-256 only; schedule, event, form and chat triggers keep their settings
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
create index if not exists workflow_triggers_definition_idx on ${t} (${ct("definition")});
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
grant select on ${t} to authenticated;
grant all on ${t} to service_role;
drop policy if exists workflow_triggers_read on ${t};
create policy workflow_triggers_read on ${t} for select to authenticated
  using (${definitionReadable(ct("definition"))});

create table if not exists ${w} (
  ${cw("tokenHash")} bytea primary key,
  ${cw("trigger")} uuid not null unique references ${t} (${ct("id")}) on delete cascade,
  ${cw("createdAt")} timestamptz not null default now()
);
alter table ${w} enable row level security;
revoke all on ${w} from anon, authenticated;
grant all on ${w} to service_role;

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
);
create index if not exists workflow_credentials_created_by_idx on ${c} (${cc("createdBy")});
alter table ${c} enable row level security;
revoke all on ${c} from anon, authenticated;
grant select on ${c} to authenticated;
grant all on ${c} to service_role;
drop policy if exists workflow_credentials_read on ${c};
create policy workflow_credentials_read on ${c} for select to authenticated
  using (${readable(cc("tenant"))});

-- The steps the deployment provides, synced from code: the palette of the
-- builder and the names a published graph may use.
create table if not exists ${l} (
  ${cl("name")} text primary key check (${cl("name")} ~ '^[A-Za-z][A-Za-z0-9_.-]{0,99}$'),
  ${cl("title")} text not null check (length(${cl("title")}) between 1 and 200),
  ${cl("description")} text,
  ${cl("inputSchema")} jsonb not null default '{}'::jsonb,
  ${cl("outputSchema")} jsonb not null default '{}'::jsonb,
  ${cl("credentialKind")} text,
  ${cl("updatedAt")} timestamptz not null default now()
);
alter table ${l} enable row level security;
revoke all on ${l} from anon, authenticated;
grant select on ${l} to authenticated;
grant all on ${l} to service_role;
drop policy if exists workflow_step_library_read on ${l};
create policy workflow_step_library_read on ${l} for select to authenticated using (true);

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
);
alter table ${n} enable row level security;
revoke all on ${n} from anon, authenticated;
grant select on ${n} to authenticated;
grant all on ${n} to service_role;
drop policy if exists workflow_node_runs_read on ${n};
create policy workflow_node_runs_read on ${n} for select to authenticated
  using (${cn("run")} in (select x.${cr("id")} from ${r} x));

-- Alerts on a definition's runs: failed fires when a run fails, slow when a
-- run is still unfinished after threshold (check_workflow_alerts). Each
-- fires once per run and writes a workflow.alert outbox event.
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
alter table ${a} enable row level security;
revoke all on ${a} from anon, authenticated;
grant select on ${a} to authenticated;
grant all on ${a} to service_role;
drop policy if exists workflow_alerts_read on ${a};
create policy workflow_alerts_read on ${a} for select to authenticated
  using (${definitionReadable(ca("definition"))});

create table if not exists ${f} (
  ${cf("alert")} uuid not null references ${a} (${ca("id")}) on delete cascade,
  ${cf("run")} uuid not null references ${r} (${cr("id")}) on delete cascade,
  ${cf("firedAt")} timestamptz not null default now(),
  primary key (${cf("alert")}, ${cf("run")})
);
create index if not exists workflow_alert_fires_run_idx on ${f} (${cf("run")});
alter table ${f} enable row level security;
revoke all on ${f} from anon, authenticated;
grant all on ${f} to service_role;

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
  if v_triggers <> 1 then
    v_errors := array_append(v_errors, 'A graph has exactly one trigger node');
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
-- the service role or workflow.edit in tenant.
create or replace function ${fn("save_workflow_definition")}(
  tenant ${id},
  slug text,
  name text,
  description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${d}%rowtype;
begin
  if not ${allowed("tenant", "edit")} then
    ${forbidden("You may not edit workflows here")}
  end if;
  insert into ${d} as x (${cd("tenant")}, ${cd("slug")}, ${cd("name")}, ${cd("description")}, ${cd("createdBy")})
  values (tenant, slug, name, description, (select auth.uid()))
  on conflict on constraint workflow_definitions_tenant_slug_key do update set
    ${cd("name")} = excluded.${cd("name")},
    ${cd("description")} = excluded.${cd("description")},
    ${cd("updatedAt")} = now()
  returning * into v_row;
  return ${definitionJson("v_row")};
end;
$$;
${callable(`${fn("save_workflow_definition")}(${id}, text, text, text)`)}

-- The definitions the caller may read, by name, each with the number of its
-- published version and whether it has a draft.
create or replace function ${fn("workflow_definitions_list")}(tenant ${id} default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    ${definitionJson("x")} || jsonb_build_object(
      'published', (select y.${cv("version")} from ${v} y where y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'published'),
      'draft', exists (select 1 from ${v} y where y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'draft')
    ) order by x.${cd("name")}), '[]'::jsonb)
  from ${d} x
  where workflow_definitions_list.tenant is null or x.${cd("tenant")} = workflow_definitions_list.tenant;
$$;
${callable(`${fn("workflow_definitions_list")}(${id})`)}

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
-- numbered after the last version. workflow.edit in its tenant.
create or replace function ${fn("save_workflow_draft")}(definition uuid, graph jsonb)
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
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ${allowed("v_tenant", "edit")} then
    ${forbidden("You may not edit this workflow")}
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update ${v} x set ${cv("graph")} = graph, ${cv("compiled")} = null
  where x.${cv("definition")} = definition and x.${cv("status")} = 'draft'
  returning * into v_row;
  if not found then
    insert into ${v} (${cv("definition")}, ${cv("version")}, ${cv("graph")}, ${cv("createdBy")})
    values (
      definition,
      coalesce((select max(y.${cv("version")}) from ${v} y where y.${cv("definition")} = definition), 0) + 1,
      graph,
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update ${d} x set ${cd("updatedAt")} = now() where x.${cd("id")} = definition;
  return ${versionJson("v_row", true)};
end;
$$;
${callable(`${fn("save_workflow_draft")}(uuid, jsonb)`)}

-- Publishes a version: workflow.publish in its tenant, and a graph
-- validate_workflow_graph accepts. The version published before is
-- archived. Only the service role may store the engine's compiled form,
-- also on a version that is already published.
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
begin
  select * into v_row from ${v} x where x.${cv("id")} = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = v_row.${cv("definition")};
  if not ${allowed("v_tenant", "publish")} then
    ${forbidden("You may not publish this workflow")}
  end if;
  if compiled is not null and not (${SERVICE_CALLER}) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
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
  update ${v} x set ${cv("status")} = 'archived'
  where x.${cv("definition")} = v_row.${cv("definition")} and x.${cv("status")} = 'published';
  update ${v} x set ${cv("status")} = 'published', ${cv("compiled")} = compiled, ${cv("publishedAt")} = now()
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

-- What a run of definition starts from: its tenant and its published
-- version. workflow.run in its tenant, or the service role.
create or replace function ${fn("workflow_start_target")}(definition uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_def ${d}%rowtype;
  v_row ${v}%rowtype;
begin
  select * into v_def from ${d} x where x.${cd("id")} = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ${allowed(`v_def.${cd("tenant")}`, "run")} then
    ${forbidden("You may not run this workflow")}
  end if;
  select * into v_row from ${v} x where x.${cv("definition")} = definition and x.${cv("status")} = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  return jsonb_build_object('definition', ${definitionJson("v_def")}, 'version', ${versionJson("v_row", true)});
end;
$$;
${callable(`${fn("workflow_start_target")}(uuid)`)}

${builderRuntimeSql(s)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "validate_workflow_graph", args: ["jsonb"], returns: "jsonb" },
    {
      name: "save_workflow_definition",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "workflow_definitions_list", args: ["{id}"], returns: "jsonb" },
    { name: "workflow_definition_get", args: ["uuid"], returns: "jsonb" },
    { name: "remove_workflow_definition", args: ["uuid"], returns: "boolean" },
    { name: "save_workflow_draft", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "publish_workflow_version",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "workflow_versions_list", args: ["uuid"], returns: "jsonb" },
    { name: "workflow_version_get", args: ["uuid"], returns: "jsonb" },
    { name: "workflow_start_target", args: ["uuid"], returns: "jsonb" },
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
      name: "workflow_event_targets",
      args: ["text", "{id}"],
      returns: "jsonb",
    },
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

export const WORKFLOW_BUILDER: ModuleDefinition = {
  name: "workflow-builder",
  title: "Workflow builder",
  description:
    "Workflow definitions a tenant edits as an engine-neutral node graph, with draft, published and archived versions, triggers (webhook tokens stored hashed), credential references a CredentialProvider resolves, a synced step library, per-node run status pinged on the run's topic, and failed and slow alerts written as workflow.alert outbox events.",
  requires: ["workflows", "tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
