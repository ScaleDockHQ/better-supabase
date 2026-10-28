import type { BlockSqlContext } from "../context.ts";
import type { Machine } from "./state-machine-options.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";

/** A workflow definition slug, as `workflow_definitions` checks it. */
const SLUG = /^[a-z0-9][a-z0-9-]{0,99}$/;

/** The keys a workflow machine reads from its graph instead. */
const FROM_GRAPH = [
  "initial",
  "transitions",
  "order",
  "requiresApproval",
  "version",
] as const;

/**
 * `options.machines.<name>.workflow`: the slug of the workflow-editor
 * definition whose published version is the machine. Undefined when unset.
 */
export function workflowOf(
  record: Readonly<Record<string, unknown>>,
  where: string,
): string | undefined {
  const value = record["workflow"];

  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string" || !SLUG.test(value)) {
    throw new TypeError(
      `${where}.workflow must be a workflow definition slug, such as deal-stages`,
    );
  }

  for (const key of FROM_GRAPH) {
    if (record[key] !== undefined) {
      throw new TypeError(
        `${where}: a workflow machine reads its statuses from the workflow; leave out ${key}`,
      );
    }
  }

  if (record["lifecycle"] === false) {
    throw new TypeError(`${where}: a workflow machine keeps a lifecycle row`);
  }

  return value;
}

const GRAPH_FN = "lifecycle_graph";

/** The name `internal` lists for the graph reader. */
export const LIFECYCLE_INTERNAL: string = GRAPH_FN;

function editor(ctx: BlockSqlContext, item: Machine): BlockSqlContext {
  if (!ctx.installed("workflow-editor")) {
    throw new TypeError(
      `blocks.state-machine.options.machines.${item.name}.workflow needs the workflow-editor module`,
    );
  }

  if (!ctx.has("lifecycles", "workflowVersion")) {
    throw new TypeError(
      `blocks.state-machine.options.machines.${item.name}.workflow needs the lifecycles table's workflowVersion column`,
    );
  }

  return ctx.of("workflow-editor");
}

/**
 * The workflow version column on `subject_lifecycles` and `lifecycle_graph`,
 * which reads a published version's graph as a machine: the nodes whose
 * `config.stage` names a status are its stages, an edge path between two stages
 * (through nodes without one) is a transition, `config.returnsTo` lists the
 * earlier stages a stage may go back to, and the trigger's path picks the
 * initial status. Empty without a workflow machine.
 */
export function lifecycleWorkflowSql(
  ctx: BlockSqlContext,
  list: readonly Machine[],
): string {
  const first = list.find((item) => item.workflow !== undefined);

  if (first === undefined) {
    return "";
  }

  const builder = editor(ctx, first);
  const versions = builder.table("versions");
  const cv = (column: string): string => builder.col("versions", column);
  const life = ctx.table("lifecycles");
  const column = ctx.col("lifecycles", "workflowVersion");
  const fn = ctx.fn(GRAPH_FN);
  const graph = `(select v.${cv("graph")} from ${versions} v where v.${cv("id")} = ${GRAPH_FN}.version_id)`;

  const arrayAt = (key: string): string =>
    `case when jsonb_typeof(g.graph -> '${key}') = 'array' then g.graph -> '${key}' else '[]'::jsonb end`;

  return `
-- The workflow-editor version a workflow machine's record follows.
alter table ${life} add column if not exists ${column} uuid references ${versions} (${cv("id")}) on delete set null;
create index if not exists ${sqlIdent(`${ctx.tableName("lifecycles").name}_workflow_version_idx`)} on ${life} (${column});

-- A workflow version's graph as a machine: { initial, order, transitions }.
-- Stages are the nodes with a string config.stage, in graph order; a path
-- from one stage to the next through nodes without a stage is a transition,
-- as are the stages a stage's config.returnsTo lists. initial is the trigger's
-- own stage, else the nearest stage after a trigger, else the first stage.
-- Null when the version doesn't exist.
create or replace function ${fn}(version_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive g as (
    select ${graph} as graph
  ),
  nodes as (
    select n.value ->> 'id' as id, n.value ->> 'kind' as kind,
      case when jsonb_typeof(n.value -> 'config' -> 'stage') = 'string' then n.value -> 'config' ->> 'stage' end as stage,
      case when jsonb_typeof(n.value -> 'config' -> 'returnsTo') = 'array' then n.value -> 'config' -> 'returnsTo' else '[]'::jsonb end as back,
      n.ord
    from g, jsonb_array_elements(${arrayAt("nodes")}) with ordinality n (value, ord)
  ),
  edges as (
    select e.value ->> 'source' as source, e.value ->> 'target' as target
    from g, jsonb_array_elements(${arrayAt("edges")}) e (value)
  ),
  walk (origin, node, depth) as (
    select o.id, e.target, 1
    from nodes o join edges e on e.source = o.id
    where o.stage is not null or o.kind = 'trigger'
    union
    select w.origin, e.target, w.depth + 1
    from walk w
    join nodes m on m.id = w.node and m.stage is null
    join edges e on e.source = w.node
    where w.depth < 100
  ),
  reached as (
    select o.kind as origin_kind, o.stage as from_stage, t.stage as to_stage, min(w.depth) as depth, min(t.ord) as ord
    from walk w
    join nodes o on o.id = w.origin
    join nodes t on t.id = w.node
    where t.stage is not null
    group by o.kind, o.stage, t.stage
  ),
  stages as (
    select n.stage, min(n.ord) as ord from nodes n where n.stage is not null group by n.stage
  ),
  moves as (
    select r.from_stage, r.to_stage from reached r
    where r.from_stage is not null and r.from_stage <> r.to_stage
    union
    select n.stage, b.value #>> '{}'
    from nodes n, jsonb_array_elements(n.back) b (value)
    where n.stage is not null and jsonb_typeof(b.value) = 'string'
      and b.value #>> '{}' <> n.stage
      and exists (select 1 from stages s where s.stage = b.value #>> '{}')
  )
  select jsonb_build_object(
    'initial', coalesce(
      (select n.stage from nodes n where n.kind = 'trigger' and n.stage is not null order by n.ord limit 1),
      (select r.to_stage from reached r where r.origin_kind = 'trigger' and r.from_stage is null order by r.depth, r.ord limit 1),
      (select s.stage from stages s order by s.ord limit 1)),
    'order', coalesce((select jsonb_agg(s.stage order by s.ord) from stages s), '[]'::jsonb),
    'transitions', coalesce((select jsonb_object_agg(m.from_stage, m.targets)
      from (select x.from_stage, jsonb_agg(distinct x.to_stage order by x.to_stage) as targets from moves x group by x.from_stage) m), '{}'::jsonb))
  from g
  where g.graph is not null
$$;
${userGrant(`${fn}(uuid)`)}
`;
}

/** `v_version` and `v_number`: the published version the record pins. */
function resolve(ctx: BlockSqlContext, item: Machine): string {
  const builder = editor(ctx, item);
  const cd = (column: string): string => builder.col("definitions", column);
  const cv = (column: string): string => builder.col("versions", column);
  const tenant = `new.${sqlIdent(item.tenantColumn)}::text`;

  const system = builder.has("definitions", "scope")
    ? `d.${cd("scope")}::text = 'system'`
    : `d.${cd("tenant")} is null`;

  return `select v.${cv("id")}, v.${cv("version")} into v_version, v_number
    from ${builder.table("versions")} v
    join ${builder.table("definitions")} d on d.${cd("id")} = v.${cv("definition")}
    where d.${cd("slug")} = ${sqlString(item.workflow ?? "")}
      and v.${cv("status")}::text = 'published'
      and (d.${cd("tenant")}::text = ${tenant} or ${system})
    order by d.${cd("tenant")} is null, v.${cv("version")} desc
    limit 1;
    if v_version is null then
      ${fail("STATE_LIFECYCLE_UNPUBLISHED", "the machine's workflow has no published version", "55000")}
    end if;`;
}

function pin(ctx: BlockSqlContext, item: Machine): string {
  const l = (column: string): string => ctx.col("lifecycles", column);

  return `insert into ${ctx.table("lifecycles")} (${l("tenant")}, ${l("subjectType")}, ${l("subjectId")}, ${l("version")}, ${l("workflowVersion")})
    values (new.${sqlIdent(item.tenantColumn)}, ${sqlString(item.name)}, new.${sqlIdent(item.idColumn)}::text, v_number, v_version)
    on conflict (${l("subjectType")}, ${l("subjectId")}) do update set
      ${l("version")} = excluded.${l("version")},
      ${l("workflowVersion")} = excluded.${l("workflowVersion")},
      ${l("updatedAt")} = now();`;
}

export const WORKFLOW_DECLARE: string = `  v_version uuid;
  v_number integer;
  v_graph jsonb;
`;

/**
 * The trigger's INSERT branch for a workflow machine: pin the published
 * version, start at its initial stage, and refuse a status it has no stage
 * for.
 */
export function workflowInsert(
  ctx: BlockSqlContext,
  item: Machine,
  stageWrite: string,
): string {
  const status = `new.${sqlIdent(item.column)}`;

  return `${resolve(ctx, item)}
    v_graph := ${ctx.fn(GRAPH_FN)}(v_version);
    if ${status} is null then
      ${status} := v_graph ->> 'initial';
    end if;
    if ${status} is null or not ((v_graph -> 'order') ? ${status}::text) then
      ${fail("STATE_TRANSITION_INVALID", "that status is not a stage of the machine's workflow", "22023")}
    end if;
    ${stageWrite}
    ${pin(ctx, item)}`;
}

/**
 * The trigger's edge check for a workflow machine, against the version the
 * record pinned; a record from before the machine pins the published one.
 */
export function workflowCheck(ctx: BlockSqlContext, item: Machine): string {
  const l = (column: string): string => ctx.col("lifecycles", column);

  return `select ${l("workflowVersion")} into v_version from ${ctx.table("lifecycles")}
  where ${l("subjectType")} = ${sqlString(item.name)} and ${l("subjectId")} = new.${sqlIdent(item.idColumn)}::text;
  if v_version is null then
    ${resolve(ctx, item)}
    ${pin(ctx, item)}
  end if;
  v_graph := ${ctx.fn(GRAPH_FN)}(v_version);
  if not coalesce((v_graph -> 'transitions' -> old.${sqlIdent(item.column)}::text) ? new.${sqlIdent(item.column)}::text, false) then
    ${fail("STATE_TRANSITION_INVALID", "that status change is not allowed", "22023")}
  end if;`;
}

/** What `status_state` reads for a workflow machine: the pinned graph's order. */
export interface WorkflowState {
  readonly load: string;
  readonly order: string;
  readonly steps: string;
  readonly progress: string;
  readonly json: string;
}

export function workflowState(
  ctx: BlockSqlContext,
  item: Machine,
): WorkflowState | undefined {
  if (item.workflow === undefined) {
    return undefined;
  }

  const version = `v_life.${ctx.col("lifecycles", "workflowVersion")}`;

  return {
    load: `
      v_order := coalesce(array(select jsonb_array_elements_text(${ctx.fn(GRAPH_FN)}(${version}) -> 'order')), '{}'::text[]);`,
    order: "v_order",
    steps: "nullif(cardinality(v_order), 0)",
    progress:
      "case when v_step is null then null when cardinality(v_order) = 1 then 1 else round((v_step - 1)::numeric / (cardinality(v_order) - 1), 4) end",
    json: `, 'workflow', ${sqlString(item.workflow)}, 'workflowVersionId', ${version}`,
  };
}
