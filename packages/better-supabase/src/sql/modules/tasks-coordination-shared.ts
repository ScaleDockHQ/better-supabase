import type { BlockSqlContext } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";

/** `, 'actorId', ..., 'actorKind', ..., 'actorName', ...` for an event payload. */
export function actorPayload(n: TaskNames, profile = "null"): string {
  const actor = `${n.fn("task_actor")}(${profile})`;

  return `, 'actorId', auth.uid(), 'actorKind', ${actor} ->> 'kind', 'actorName', ${actor} ->> 'name'`;
}

/** The statement that records a task event with the actor keys. */
export function taskRecord(
  ctx: BlockSqlContext,
  n: TaskNames,
  type: string,
  alias: string,
  extra = "",
  profile = "null",
): string {
  const w = (column: string): string => n.c("items", column);

  return ctx.record({
    type,
    payload: `jsonb_build_object('organizationId', ${alias}.${w("tenant")}, 'taskId', ${alias}.${w("id")}, 'subjectType', ${sqlString(n.type)}, 'subjectId', ${alias}.${w("id")}::text, 'title', ${alias}.${w("title")}${extra}${actorPayload(n, profile)})`,
    subject: `'tasks/' || ${alias}.${w("id")}::text`,
    tenant: `${alias}.${w("tenant")}::text`,
    row: alias,
    audit: false,
    ...(n.templates ? { live: `${alias}.${w("template")} is null` } : {}),
  });
}

/**
 * The common head of a function that changes one task: load it and check
 * access.
 */
export function load(
  ctx: BlockSqlContext,
  n: TaskNames,
  fnName: string,
  permission: string,
  options: { readonly lock?: boolean } = {},
): string {
  const w = (column: string): string => n.c("items", column);

  return `select * into v_row from ${n.t("items")} x where x.${w("id")} = ${fnName}.task and x.${w("archivedAt")} is null${options.lock === false ? "" : " for update"};
  if not found then
    ${fail("TASK_NOT_FOUND", "no such work item", "P0002")}
  end if;
  if not (${n.service} or ${ctx.scope.can(`v_row.${w("tenant")}`, permission)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to change this work item")}
  end if;`;
}

export function stageByKey(
  ctx: BlockSqlContext,
  pipeline: string,
  key: string,
): string {
  const s = ctx.of("pipelines");
  const sc = (column: string): string => s.col("stages", column);

  return `(select s.${sc("id")} from ${s.table("stages")} s where s.${sc("pipeline")} = ${pipeline} and s.${sc("key")} = ${sqlString(key)} and s.${sc("archivedAt")} is null)`;
}

export function stageByCategory(
  ctx: BlockSqlContext,
  pipeline: string,
  category: string,
): string {
  const s = ctx.of("pipelines");
  const sc = (column: string): string => s.col("stages", column);

  return `(select s.${sc("id")} from ${s.table("stages")} s where s.${sc("pipeline")} = ${pipeline} and s.${sc("category")}::text = ${sqlString(category)} and s.${sc("archivedAt")} is null order by s.${sc("rank")} collate "C", s.${sc("id")} limit 1)`;
}

/** A stage named by key, or by category (the first live stage of it by rank). */
export type StageRef = string | { readonly category: string };

/** The stage of a pipeline a `StageRef` names, as a scalar subquery. */
export function stageRef(
  ctx: BlockSqlContext,
  pipeline: string,
  ref: StageRef,
): string {
  return typeof ref === "string"
    ? stageByKey(ctx, pipeline, ref)
    : stageByCategory(ctx, pipeline, ref.category);
}

/** How a message names a stage reference. */
export function stageRefLabel(ref: StageRef): string {
  return typeof ref === "string" ? `${ref} stage` : `${ref.category} category`;
}
