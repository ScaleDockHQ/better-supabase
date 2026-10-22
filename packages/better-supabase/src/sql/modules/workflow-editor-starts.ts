import type { BlockSqlContext } from "../context.ts";
import type { BuilderSql } from "./workflow-editor-sql.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, fail } from "../shared.ts";

export const GRANT_PRINCIPALS = ["user", "team", "role"] as const;

export const GRANT_ACTIONS = ["run", "edit"] as const;

/** `values` as a SQL list of string literals. */
export const sqlList = (values: readonly string[]): string =>
  values.map(sqlString).join(", ");

/**
 * How runs start (`workflow_start_target`, its subject variant and
 * `start_test_run`), and who may run a definition: forks, opt-outs and grants.
 */
export function builderStartsSql(ctx: BlockSqlContext, s: BuilderSql): string {
  const {
    id,
    fn,
    d,
    v,
    o,
    g,
    cd,
    cv,
    co,
    cg,
    allowed,
    granted,
    optedOut,
    forbidden,
    callable,
    definitionJson,
    versionJson,
  } = s;

  return `-- What a run of definition starts from: the tenant it runs in and the
-- published version. workflow.run in that tenant (and a run grant on a
-- restricted definition), or the service role. A system definition runs in
-- tenant, which it needs; a tenant that opted out of the definition gets
-- WORKFLOW_OPTED_OUT.
drop function if exists ${fn("workflow_start_target")}(uuid);
create or replace function ${fn("workflow_start_target")}(definition uuid, tenant ${id} default null)
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
  v_tenant ${id};
begin
  select * into v_def from ${d} x where x.${cd("id")} = definition;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  v_tenant := case when v_def.${cd("scope")} = 'system' then tenant else v_def.${cd("tenant")} end;
  if v_def.${cd("scope")} = 'system' and v_tenant is null then
    ${fail("WORKFLOW_TENANT_REQUIRED", "Pass the tenant a system workflow runs in", "22023")}
  end if;
  if not (${allowed("v_tenant", "run")} and ${granted("definition", "v_tenant", "run")}) then
    ${forbidden("You may not run this workflow")}
  end if;
  if v_tenant is not null and ${optedOut("definition", "v_tenant")} then
    ${fail("WORKFLOW_OPTED_OUT", "This organization opted out of this workflow", "P0001")}
  end if;
  select * into v_row from ${v} x where x.${cv("definition")} = definition and x.${cv("status")} = 'published';
  if not found then
    ${fail("WORKFLOW_NOT_PUBLISHED", "This workflow has no published version", "P0002")}
  end if;
  return jsonb_build_object('definition', ${definitionJson("v_def")}, 'version', ${versionJson("v_row", true)}, 'tenant', v_tenant);
end;
$$;
${callable(`${fn("workflow_start_target")}(uuid, ${id})`)}

-- workflow_start_target for a run that belongs to a record: the definition
-- must list subject_type in subject_types${ctx.installed("subjects") ? ", and the caller must be able to read the record (can_subject)" : ""}. Security invoker, so the
-- record check runs under the caller's RLS; returns the target with the
-- subject.
create or replace function ${fn("workflow_subject_start_target")}(
  definition uuid,
  subject_type text,
  subject_id text,
  tenant ${id} default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_types text[];
begin
  if subject_type is null or subject_id is null or length(subject_type) not between 1 and 100 or length(subject_id) not between 1 and 200 then
    ${fail("WORKFLOW_SUBJECT_INVALID", "A subject has a type of 1 to 100 and an id of 1 to 200 characters", "22023")}
  end if;
  select x.${cd("subjectTypes")} into v_types from ${d} x where x.${cd("id")} = definition;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  if not (subject_type = any (v_types)) then
    ${fail("WORKFLOW_SUBJECT_TYPE", "This workflow doesn't run on that subject type", "22023")}
  end if;${
    ctx.installed("subjects")
      ? `
  if not (${SERVICE_CALLER}) and not coalesce(${ctx.of("subjects").fn("can_subject")}(subject_type, subject_id, 'read'), false) then
    ${forbidden("You may not run a workflow on this record")}
  end if;`
      : ""
  }
  return ${fn("workflow_start_target")}(definition, tenant)
    || jsonb_build_object('subject', jsonb_build_object('type', subject_type, 'id', subject_id));
end;
$$;
${callable(`${fn("workflow_subject_start_target")}(uuid, text, text, ${id})`)}

-- What a test run of definition starts from: version (default its draft,
-- else its published version), the trigger node it starts at (default the
-- graph's only trigger) and the stubs its steps return. workflow.edit in its
-- tenant (and an edit grant on a restricted definition). The run records
-- mode test: its steps don't run, and it fires no alerts and writes no
-- outbox events.
create or replace function ${fn("start_test_run")}(
  definition uuid,
  version uuid default null,
  trigger_node text default null,
  input jsonb default null,
  stubs jsonb default null
)
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
  v_errors jsonb;
  v_triggers text[];
  v_node text := trigger_node;
begin
  select * into v_def from ${d} x where x.${cd("id")} = definition;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  if not (${allowed(`v_def.${cd("tenant")}`, "edit")} and ${granted("definition", `v_def.${cd("tenant")}`, "edit")}) then
    ${forbidden("You may not test this workflow")}
  end if;
  if stubs is not null and jsonb_typeof(stubs) <> 'object' then
    ${fail("WORKFLOW_STUBS_INVALID", "stubs is an object keyed by node id", "22023")}
  end if;
  select * into v_row from ${v} x
  where x.${cv("definition")} = definition
    and (case when version is null then x.${cv("status")} in ('draft', 'published') else x.${cv("id")} = version end)
  order by x.${cv("status")} = 'draft' desc
  limit 1;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow version", "P0002")}
  end if;
  v_errors := ${fn("validate_workflow_graph")}(v_row.${cv("graph")});
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  select array_agg(n.value ->> 'id') into v_triggers
  from jsonb_array_elements(v_row.${cv("graph")} -> 'nodes') n
  where n.value ->> 'kind' = 'trigger';
  if v_node is null and cardinality(v_triggers) = 1 then
    v_node := v_triggers[1];
  end if;
  if v_node is null or not (v_node = any (v_triggers)) then
    ${fail("WORKFLOW_TRIGGER_NODE", "Pass trigger_node, the id of one of the graph's trigger nodes", "22023")}
  end if;
  return jsonb_build_object(
    'definition', ${definitionJson("v_def")},
    'version', ${versionJson("v_row", true)},
    'tenant', v_def.${cd("tenant")},
    'triggerNode', v_node,
    'input', coalesce(input, '{}'::jsonb),
    'stubs', coalesce(stubs, '{}'::jsonb)
  );
end;
$$;
${callable(`${fn("start_test_run")}(uuid, uuid, text, jsonb, jsonb)`)}

-- Copies the published graph of source (a system definition, or one in
-- tenant) into a new definition in tenant with slug, as its draft, and
-- records the version it copied. workflow.edit in tenant (and an edit grant
-- on a restricted source).
create or replace function ${fn("fork_workflow_definition")}(source uuid, tenant ${id}, slug text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_src ${d}%rowtype;
  v_version ${v}%rowtype;
  v_row ${d}%rowtype;
begin
  select * into v_src from ${d} x where x.${cd("id")} = source;
  if not found or not (v_src.${cd("scope")} = 'system' or v_src.${cd("tenant")} is not distinct from tenant) then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  if not ${allowed("tenant", "edit")} then
    ${forbidden("You may not edit workflows here")}
  end if;
  if v_src.${cd("scope")} = 'tenant' and not ${granted("source", "tenant", "edit")} then
    ${forbidden("You may not fork this workflow")}
  end if;
  select * into v_version from ${v} x where x.${cv("definition")} = source and x.${cv("status")} = 'published';
  if not found then
    ${fail("WORKFLOW_NOT_PUBLISHED", "This workflow has no published version", "P0002")}
  end if;
  insert into ${d} (${cd("tenant")}, ${cd("slug")}, ${cd("name")}, ${cd("description")}, ${cd("subjectTypes")}, ${cd("forkedFrom")}, ${cd("forkedFromVersion")}, ${cd("createdBy")})
  values (tenant, slug, v_src.${cd("name")}, v_src.${cd("description")}, v_src.${cd("subjectTypes")}, v_src.${cd("id")}, v_version.${cv("version")}, (select auth.uid()))
  returning * into v_row;
  insert into ${v} (${cv("definition")}, ${cv("version")}, ${cv("graph")}, ${cv("inputSchema")}, ${cv("createdBy")})
  values (v_row.${cd("id")}, 1, v_version.${cv("graph")}, v_version.${cv("inputSchema")}, (select auth.uid()));
  return ${definitionJson("v_row")} || jsonb_build_object('draft', true, 'upstreamVersion', v_version.${cv("version")}, 'behind', false);
end;
$$;
${callable(`${fn("fork_workflow_definition")}(uuid, ${id}, text)`)}

-- Opts tenant out of definition (a system definition, or one in tenant), or
-- back in with opted_out false: workflow.admin in tenant. Returns whether
-- the tenant is opted out.
create or replace function ${fn("set_workflow_opt_out")}(tenant ${id}, definition uuid, opted_out boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if tenant is null then
    ${fail("WORKFLOW_TENANT_REQUIRED", "Pass the tenant that opts out", "22023")}
  end if;
  if not ${allowed("tenant", "admin")} then
    ${forbidden("You may not manage workflows here")}
  end if;
  if not exists (
    select 1 from ${d} x
    where x.${cd("id")} = definition and (x.${cd("scope")} = 'system' or x.${cd("tenant")} = tenant)
  ) then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  if coalesce(opted_out, true) then
    insert into ${o} (${co("tenant")}, ${co("definition")}, ${co("createdBy")})
    values (tenant, definition, (select auth.uid()))
    on conflict do nothing;
  else
    delete from ${o} x where x.${co("tenant")} = tenant and x.${co("definition")} = definition;
  end if;
  return coalesce(opted_out, true);
end;
$$;
${callable(`${fn("set_workflow_opt_out")}(${id}, uuid, boolean)`)}

-- Grants (or with granted false, revokes) action (run or edit) on a
-- definition to a user, a team or an organization role: workflow.admin in
-- its tenant. Grants only matter while the definition is restricted.
create or replace function ${fn("set_workflow_definition_grant")}(
  definition uuid,
  principal_kind text,
  principal_id text,
  action text,
  granted boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${id};
begin
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = definition;
  if not found then
    ${fail("WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  if not ${allowed("v_tenant", "admin")} then
    ${forbidden("You may not manage access to this workflow")}
  end if;
  if principal_kind is null or principal_kind not in (${sqlList(GRANT_PRINCIPALS)}) then
    ${fail("WORKFLOW_GRANT_INVALID", "principal_kind is user, team or role", "22023")}
  end if;
  if action is null or action not in (${sqlList(GRANT_ACTIONS)}) then
    ${fail("WORKFLOW_GRANT_INVALID", "action is run or edit", "22023")}
  end if;
  if coalesce(granted, true) then
    insert into ${g} (${cg("definition")}, ${cg("principalKind")}, ${cg("principalId")}, ${cg("action")}, ${cg("createdBy")})
    values (definition, principal_kind, principal_id, action, (select auth.uid()))
    on conflict on constraint ${ctx.naming.rename("workflow_definition_grants_key")} do nothing;
  else
    delete from ${g} x
    where x.${cg("definition")} = definition and x.${cg("principalKind")} = principal_kind
      and x.${cg("principalId")} = principal_id and x.${cg("action")} = action;
  end if;
  return coalesce(granted, true);
end;
$$;
${callable(`${fn("set_workflow_definition_grant")}(uuid, text, text, text, boolean)`)}

create or replace function ${fn("workflow_definition_grants_list")}(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.${cg("id")},
    'definition', x.${cg("definition")},
    'principalKind', x.${cg("principalKind")},
    'principalId', x.${cg("principalId")},
    'action', x.${cg("action")},
    'createdBy', x.${cg("createdBy")},
    'createdAt', x.${cg("createdAt")}
  ) order by x.${cg("createdAt")}), '[]'::jsonb)
  from ${g} x where x.${cg("definition")} = workflow_definition_grants_list.definition;
$$;
${callable(`${fn("workflow_definition_grants_list")}(uuid)`)}`;
}
