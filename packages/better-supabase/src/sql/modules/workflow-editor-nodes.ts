import type { BlockSqlContext } from "../context.ts";
import type { BuilderSql } from "./workflow-editor-sql.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, serviceGrant } from "../shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { sqlList as list } from "./workflow-editor-starts.ts";

/** The node kinds every graph may use; the registry adds the app's own. */
const WORKFLOW_BUILTIN_NODE_KINDS = [
  "trigger",
  "step",
  "sleep",
  "approval",
  "condition",
] as const;

const BRANCHING = ["condition", "approval"] as const;

/** What a definition is for: `lifecycle` owns a record's status path. */
const WORKFLOW_PURPOSES = ["automation", "lifecycle"] as const;

/**
 * The node kind registry: the app's own kinds (`defineNodeKind`), synced by
 * `sync_workflow_node_kinds`, which graphs may use next to the built-in ones.
 */
export function nodeKindsDdl(ctx: BlockSqlContext): string {
  const k = ctx.table("nodeKinds");
  const ck = (column: string): string => ctx.col("nodeKinds", column);

  return `-- The app's own node kinds (defineNodeKind), synced from code. branches:
-- whether the kind's edges take a true or false branch.
create table if not exists ${k} (
  ${ck("kind")} text primary key check (${ck("kind")} ~ '^[a-z][a-z0-9_.-]{0,62}$' and ${ck("kind")} not in (${list(WORKFLOW_BUILTIN_NODE_KINDS)})),
  ${ck("title")} text not null check (length(${ck("title")}) between 1 and 200),
  ${ck("description")} text,
  ${ck("branches")} boolean not null default false,
  ${ck("configSchema")} jsonb not null default '{}'::jsonb,
  ${ck("updatedAt")} timestamptz not null default now()
);${appUniqueIndex(ctx, "nodeKinds", ["kind"])}
${lockModuleTable(ctx, "nodeKinds", { read: true })}
${renderPolicy(makePolicy({ table: k, name: "workflow_node_kinds_read", command: "select", roles: ["authenticated"], using: "true" }), { drop: true, target: k })}`;
}

/** The registry's sync and list functions and `validate_workflow_graph`. */
export function nodeKindsSql(ctx: BlockSqlContext, s: BuilderSql): string {
  const { fn, l, cl, callable } = s;
  const k = ctx.table("nodeKinds");
  const ck = (column: string): string => ctx.col("nodeKinds", column);

  const nodeKindJson = (alias: string): string => `jsonb_build_object(
    'kind', ${alias}.${ck("kind")},
    'title', ${alias}.${ck("title")},
    'description', ${alias}.${ck("description")},
    'branches', ${alias}.${ck("branches")},
    'configSchema', ${alias}.${ck("configSchema")},
    'updatedAt', ${alias}.${ck("updatedAt")}
  )`;

  return `-- Replaces the node kind registry with kinds, keyed by kind ({ kind: {
-- title, description, branches, configSchema } }); returns how many there are.
create or replace function ${fn("sync_workflow_node_kinds")}(kinds jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  if jsonb_typeof(coalesce(kinds, '{}'::jsonb)) <> 'object' then
    ${fail("WORKFLOW_NODE_KINDS", "kinds is an object keyed by kind")}
  end if;
  insert into ${k} (${ck("kind")}, ${ck("title")}, ${ck("description")}, ${ck("branches")}, ${ck("configSchema")})
  select e.key, coalesce(e.value ->> 'title', e.key), e.value ->> 'description',
    coalesce((e.value ->> 'branches')::boolean, false), coalesce(e.value -> 'configSchema', '{}'::jsonb)
  from jsonb_each(coalesce(kinds, '{}'::jsonb)) e
  on conflict (${ck("kind")}) do update set
    ${ck("title")} = excluded.${ck("title")},
    ${ck("description")} = excluded.${ck("description")},
    ${ck("branches")} = excluded.${ck("branches")},
    ${ck("configSchema")} = excluded.${ck("configSchema")},
    ${ck("updatedAt")} = now();
  delete from ${k} x
  where not exists (
    select 1 from jsonb_each(coalesce(kinds, '{}'::jsonb)) e where e.key = x.${ck("kind")}
  );
  select count(*) into v_count from ${k};
  return v_count;
end;
$$;
${serviceGrant(`${fn("sync_workflow_node_kinds")}(jsonb)`)}

create or replace function ${fn("workflow_node_kinds_list")}()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${nodeKindJson("x")} order by x.${ck("kind")}), '[]'::jsonb) from ${k} x;
$$;
${callable(`${fn("workflow_node_kinds_list")}()`)}

-- Problems that keep a graph from being published, as messages; empty when
-- it may be. A node's kind is built in or in the node kind registry, step
-- names are in the step library, and only a branching kind's edges take a
-- branch.
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
  v_branching text[] := '{}';
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
    if coalesce(v_node ->> 'kind', '') in (${list(BRANCHING)}) or exists (
      select 1 from ${k} x where x.${ck("kind")} = v_node ->> 'kind' and x.${ck("branches")}
    ) then
      v_branching := array_append(v_branching, v_node ->> 'id');
    end if;
    if coalesce(v_node ->> 'kind', '') not in (${list(WORKFLOW_BUILTIN_NODE_KINDS)}) and not exists (
      select 1 from ${k} x where x.${ck("kind")} = v_node ->> 'kind'
    ) then
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
    elsif v_edge ? 'branch' and not ((v_edge ->> 'source') = any (v_branching)) then
      v_errors := array_append(v_errors, format('Edge %s takes a branch from a node that does not branch', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$$;
${callable(`${fn("validate_workflow_graph")}(jsonb)`)}`;
}

/**
 * `set_workflow_definition_purpose` and `resolve_workflow_definition`, when
 * definitions have the purpose and default columns.
 */
export function definitionPurposeSql(
  ctx: BlockSqlContext,
  s: BuilderSql,
): string {
  if (
    !(ctx.has("definitions", "purpose") && ctx.has("definitions", "isDefault"))
  ) {
    return "";
  }

  const {
    id,
    fn,
    d,
    v,
    cd,
    cv,
    allowed,
    forbidden,
    callable,
    definitionJson,
    versionJson,
    optedOut,
    scoped,
    subjectTyped,
  } = s;

  const overlap = subjectTyped
    ? `\n      and x.${cd("subjectTypes")} && v_row.${cd("subjectTypes")}`
    : "";

  const subject = subjectTyped
    ? `\n    and (resolve_workflow_definition.subject_type is null or resolve_workflow_definition.subject_type = any (x.${cd("subjectTypes")}))`
    : "";

  const system = scoped
    ? `\n      or (x.${cd("scope")} = 'system' and not ${optedOut(`x.${cd("id")}`, "resolve_workflow_definition.tenant")})`
    : "";

  return `create index if not exists ${ctx.naming.rename("workflow_definitions_default_idx")} on ${d} (${cd("tenant")}, ${cd("purpose")}) where ${cd("isDefault")};

-- Sets what a definition is for and whether it is its tenant's default
-- (workflow.admin, or the service role for a system one). Only a lifecycle
-- definition is a default; marking one clears the default from the other
-- lifecycle definitions of its tenant that share a subject type.
create or replace function ${fn("set_workflow_definition_purpose")}(
  definition uuid,
  purpose text,
  is_default boolean default false
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
  if purpose is null or purpose not in (${list(WORKFLOW_PURPOSES)}) then
    ${fail("WORKFLOW_PURPOSE_INVALID", "purpose is automation or lifecycle")}
  end if;
  select * into v_row from ${d} x where x.${cd("id")} = definition for update;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "Workflow definition not found")}
  end if;
  if not ${allowed(`v_row.${cd("tenant")}`, "admin")} then
    ${forbidden("Changing what a workflow is for needs workflow.admin")}
  end if;
  if coalesce(is_default, false) and purpose <> 'lifecycle' then
    ${fail("WORKFLOW_PURPOSE_INVALID", "Only a lifecycle workflow is a default")}
  end if;${
    subjectTyped
      ? `
  if purpose = 'lifecycle' and cardinality(v_row.${cd("subjectTypes")}) = 0 then
    ${fail("WORKFLOW_PURPOSE_INVALID", "A lifecycle workflow names its subject types")}
  end if;`
      : ""
  }
  if coalesce(is_default, false) then
    update ${d} x set ${cd("isDefault")} = false
    where x.${cd("tenant")} is not distinct from v_row.${cd("tenant")}
      and x.${cd("id")} <> v_row.${cd("id")}
      and x.${cd("isDefault")}${overlap};
  end if;
  update ${d} x set
    ${cd("purpose")} = purpose,
    ${cd("isDefault")} = coalesce(is_default, false),
    ${cd("updatedAt")} = now()
  where x.${cd("id")} = v_row.${cd("id")}
  returning * into v_row;
  return ${definitionJson("v_row")};
end;
$$;
${callable(`${fn("set_workflow_definition_purpose")}(uuid, text, boolean)`)}

-- The default definition for purpose in tenant and its published version:
-- the tenant's own default first, then a system default the tenant didn't
-- opt out of. subject_type, when given, picks a default that names it. Null
-- when none is published or the caller may not read it.
create or replace function ${fn("resolve_workflow_definition")}(
  tenant ${id},
  purpose text default 'lifecycle',
  subject_type text default null
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('definition', ${definitionJson("x")}, 'version', ${versionJson("y", false)})
  from ${d} x
  join ${v} y on y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'published'
  where x.${cd("isDefault")}
    and x.${cd("purpose")} = resolve_workflow_definition.purpose${subject}
    and (x.${cd("tenant")} = resolve_workflow_definition.tenant${system})
  order by (x.${cd("tenant")} is null), x.${cd("updatedAt")} desc
  limit 1;
$$;
${callable(`${fn("resolve_workflow_definition")}(${id}, text, text)`)}`;
}
