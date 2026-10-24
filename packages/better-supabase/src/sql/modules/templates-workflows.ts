import type { BlockSqlContext } from "../context.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

export interface WorkflowParts {
  readonly ddl: string;
  /** Statements in `fork_template` that copy the source's attachments. */
  readonly forkCopy: string;
  /** Statements in `template_apply_target` that fill `v_workflows`. */
  readonly applyTarget: string;
  readonly functions: string;
}

/**
 * The workflows a template starts on the record it creates, with the
 * workflow-editor module: the attachment table, the input check against a
 * version's `input_schema`, and attach, detach and list.
 */
export function workflowParts(
  ctx: BlockSqlContext,
  shared: {
    readonly builder: BlockSqlContext;
    readonly schemas: boolean;
    readonly mayManage: (tenant: string) => string;
  },
): WorkflowParts {
  const { builder } = shared;
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("templates");
  const wf = ctx.table("workflows");
  const ct = (column: string): string => ctx.col("templates", column);
  const cw = (column: string): string => ctx.col("workflows", column);
  const d = builder.table("definitions");
  const v = builder.table("versions");
  const cd = (column: string): string => builder.col("definitions", column);
  const cv = (column: string): string => builder.col("versions", column);
  const errors = fn("template_workflow_input_errors");

  // A system definition has no tenant; the scope column, when the app keeps
  // one, says so too.
  const systemDefinition = builder.has("definitions", "scope")
    ? `v_def.${cd("scope")} = 'system'`
    : `v_def.${cd("tenant")} is null`;

  const fullCheck = shared.schemas
    ? `
  if cardinality(v_errors) = 0 then
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, inputs::json);
  end if;`
    : "";

  const workflowJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${cw("id")},
    'template', ${alias}.${cw("template")},
    'definition', ${alias}.${cw("definition")},
    'inputs', ${alias}.${cw("inputs")},
    'enabled', ${alias}.${cw("enabled")},
    'createdBy', ${alias}.${cw("createdBy")},
    'createdAt', ${alias}.${cw("createdAt")}
  )`;

  return {
    ddl: `
-- The workflow definitions a template starts on each record it creates, with
-- the input each run takes.
create table if not exists ${wf} (
  ${cw("id")} uuid primary key default gen_random_uuid(),
  ${cw("template")} uuid not null references ${t} (${ct("id")}) on delete cascade,
  ${cw("definition")} uuid not null references ${d} (${cd("id")}) on delete cascade,
  ${cw("inputs")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${cw("inputs")}) = 'object'),
  ${cw("enabled")} boolean not null default true,
  ${cw("createdBy")} uuid references auth.users (id) on delete set null,
  ${cw("createdAt")} timestamptz not null default now(),
  constraint template_workflows_template_definition_key unique (${cw("template")}, ${cw("definition")})
);
create index if not exists template_workflows_definition_idx on ${wf} (${cw("definition")});
create index if not exists template_workflows_created_by_idx on ${wf} (${cw("createdBy")});
${lockModuleTable(ctx, "workflows", { read: true })}
drop policy if exists template_workflows_read on ${wf};
create policy template_workflows_read on ${wf} for select to authenticated
  using (exists (select 1 from ${t} x where x.${ct("id")} = ${cw("template")}));

-- Why inputs don't match the input_schema of definition's published version:
-- empty when it matches, has no published version or no schema. The
-- required keys are always checked${shared.schemas ? ", then the whole schema" : ""}.
create or replace function ${errors}(definition uuid, inputs jsonb)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_schema jsonb;
  v_errors text[];
begin
  select y.${cv("inputSchema")} into v_schema from ${v} y
  where y.${cv("definition")} = template_workflow_input_errors.definition and y.${cv("status")} = 'published';
  if v_schema is null then
    return '{}';
  end if;
  if jsonb_typeof(inputs) <> 'object' then
    return array['inputs must be an object'];
  end if;
  select coalesce(array_agg('missing required input ' || k order by k), '{}') into v_errors
  from jsonb_array_elements_text(case when jsonb_typeof(v_schema -> 'required') = 'array' then v_schema -> 'required' else '[]'::jsonb end) k
  where not (inputs ? k);${fullCheck}
  return v_errors;
end;
$$;
${serviceGrant(`${errors}(uuid, jsonb)`)}
`,
    forkCopy: `  insert into ${wf} (${cw("template")}, ${cw("definition")}, ${cw("inputs")}, ${cw("enabled")}, ${cw("createdBy")})
  select v_row.${ct("id")}, w.${cw("definition")}, w.${cw("inputs")}, w.${cw("enabled")}, (select auth.uid())
  from ${wf} w where w.${cw("template")} = v_src.${ct("id")};
`,
    applyTarget: `  select coalesce(jsonb_agg(jsonb_build_object(
      'definition', w.${cw("definition")},
      'inputs', w.${cw("inputs")},
      'errors', to_jsonb(${errors}(w.${cw("definition")}, w.${cw("inputs")})))
    order by w.${cw("createdAt")}, w.${cw("id")}), '[]'::jsonb)
  into v_workflows
  from ${wf} w where w.${cw("template")} = v_tpl.${ct("id")} and w.${cw("enabled")};
  if exists (select 1 from jsonb_array_elements(v_workflows) e where jsonb_array_length(e.value -> 'errors') > 0) then
    raise exception 'A workflow input does not match its input schema: %',
      (select string_agg(e.value ->> 'definition' || ': ' || (e.value -> 'errors' ->> 0), '; ')
        from jsonb_array_elements(v_workflows) e where jsonb_array_length(e.value -> 'errors') > 0)
      using errcode = '22023', hint = 'TEMPLATE_WORKFLOW_INPUT_INVALID';
  end if;
  select coalesce(jsonb_agg(e.value - 'errors'), '[]'::jsonb) into v_workflows from jsonb_array_elements(v_workflows) e;
`,
    functions: `
-- Starts definition on every record template creates, with inputs as the
-- run's input. The definition must be in the template's tenant or a system
-- one; inputs are checked against its published input_schema.
create or replace function ${fn("attach_template_workflow")}(template_id uuid, definition uuid, inputs jsonb, enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
  v_def ${d}%rowtype;
  v_errors text[];
  v_row ${wf}%rowtype;
begin
  select * into v_tpl from ${t} x where x.${ct("id")} = attach_template_workflow.template_id;
  if not found then
    ${fail("TEMPLATE_NOT_FOUND", "No such template", "P0002")}
  end if;
  if not ${shared.mayManage(`v_tpl.${ct("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not change this template")}
  end if;
  select * into v_def from ${d} x where x.${cd("id")} = attach_template_workflow.definition;
  if not found or not (${systemDefinition} or v_def.${cd("tenant")} is not distinct from v_tpl.${ct("tenant")}) then
    ${fail("TEMPLATE_WORKFLOW_NOT_FOUND", "No such workflow", "P0002")}
  end if;
  v_errors := ${errors}(attach_template_workflow.definition, coalesce(attach_template_workflow.inputs, '{}'::jsonb));
  if cardinality(v_errors) > 0 then
    raise exception 'The workflow input does not match its input schema: %', v_errors[1]
      using errcode = '22023', hint = 'TEMPLATE_WORKFLOW_INPUT_INVALID';
  end if;
  insert into ${wf} as w (${cw("template")}, ${cw("definition")}, ${cw("inputs")}, ${cw("enabled")}, ${cw("createdBy")})
  values (v_tpl.${ct("id")}, attach_template_workflow.definition,
    coalesce(attach_template_workflow.inputs, '{}'::jsonb), coalesce(attach_template_workflow.enabled, true), (select auth.uid()))
  on conflict on constraint template_workflows_template_definition_key do update set
    ${cw("inputs")} = excluded.${cw("inputs")},
    ${cw("enabled")} = excluded.${cw("enabled")}
  returning * into v_row;
  return ${workflowJson("v_row")};
end;
$$;
${userGrant(`${fn("attach_template_workflow")}(uuid, uuid, jsonb, boolean)`)}

create or replace function ${fn("detach_template_workflow")}(template_id uuid, definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tpl ${t}%rowtype;
begin
  select * into v_tpl from ${t} x where x.${ct("id")} = detach_template_workflow.template_id;
  if not found then
    return false;
  end if;
  if not ${shared.mayManage(`v_tpl.${ct("tenant")}`)} then
    ${fail("TEMPLATE_FORBIDDEN", "You may not change this template")}
  end if;
  delete from ${wf} w where w.${cw("template")} = detach_template_workflow.template_id
    and w.${cw("definition")} = detach_template_workflow.definition;
  return found;
end;
$$;
${userGrant(`${fn("detach_template_workflow")}(uuid, uuid)`)}

create or replace function ${fn("template_workflows_list")}(template_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${workflowJson("w")} order by w.${cw("createdAt")}, w.${cw("id")}), '[]'::jsonb)
  from ${wf} w where w.${cw("template")} = template_workflows_list.template_id
$$;
${userGrant(`${fn("template_workflows_list")}(uuid)`)}
`,
  };
}
