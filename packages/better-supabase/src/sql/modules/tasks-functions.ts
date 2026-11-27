/* oxlint-disable eslint/max-lines -- project fields, identifiers and iteration capacity add lines past the limit. 1 finding. */
import type { ExtraColumn, BlockSqlContext } from "../context.ts";
import type { Coordination } from "./tasks-coordination.ts";

import { STALE_WRITE, STALE_WRITE_SQLSTATE } from "../../core/stale-write.ts";
import { sqlString } from "../../core/template.ts";
import { booksAccounting } from "../accounting-sources-sql.ts";
import { int8Text } from "../money-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { entityType } from "../resolved-names.ts";
import {
  fail,
  insertExtraColumns,
  pageSize,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { watchSql } from "../watch-sql.ts";
import { asText } from "./over-app.ts";
import { actorPayload } from "./tasks-coordination-shared.ts";
import {
  claimReadSql,
  coordinationSql,
  taskRecord,
} from "./tasks-coordination.ts";
import {
  itemExtrasJson,
  linkAttachmentsSql,
  taskExtraFunctions,
} from "./tasks-extras.ts";
import { projectProgressSql, taskPageSql } from "./tasks-pages.ts";
import {
  projectIdentifierSql,
  projectWorkFunctions,
} from "./tasks-projects.ts";
import { cloneTenant } from "./templates-clone.ts";

export interface TaskNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly create: string;
  readonly remove: string;
  readonly authorCanDelete: boolean;
  readonly notify: boolean;
  readonly actionPath: string;
  /** The identifier prefix without numbering, such as `TASK-`. */
  readonly prefix: string;
  /** The most assignees an item takes; 0 for no limit. */
  readonly maxAssignees: number;
  readonly service: string;
  /**
   * The columns your schema files add: create writes them from attrs.fields,
   * update by name.
   */
  readonly extras: readonly ExtraColumn[];
  /**
   * An entity name, event type or payload key after `blocks.tasks.names`:
   * `task` to `ticket`, `projectId` to `initiativeId`.
   */
  readonly e: (name: string) => string;
  /** The subject type of a task (`task`, or its renamed singular). */
  readonly type: string;
  /** Template rows are enabled (ADR 0244). */
  readonly templates: boolean;
  /** The prerequisite, claim and hold options (ADRs 1110 to 1114). */
  readonly co: Coordination;
}

/**
 * The fields `update_tasks` writes, by camelCase name, with the logical column
 * each one writes.
 */
function fields(
  ctx: BlockSqlContext,
  w: (column: string) => string,
  e: (name: string) => string,
): readonly {
  readonly field: string;
  readonly column: string;
  readonly set: (v: string) => string;
}[] {
  const text = (column: string) => (v: string) =>
    `${w(column)} = nullif(trim(${v} #>> '{}'), '')`;

  const cast = (column: string, type: string) => (v: string) =>
    `${w(column)} = (${v} #>> '{}')::${type}`;

  return [
    {
      field: "title",
      column: "title",
      set: (v) => `${w("title")} = trim(${v} #>> '{}')`,
    },
    { field: "body", column: "body", set: text("body") },
    { field: "parentId", column: "parent", set: cast("parent", "uuid") },
    { field: "teamId", column: "team", set: cast("team", "uuid") },
    { field: e("projectId"), column: "project", set: cast("project", "uuid") },
    {
      field: e("iterationId"),
      column: "iteration",
      set: cast("iteration", "uuid"),
    },
    {
      field: "priority",
      column: "priority",
      set: ctx.mapsValues("items", "priority")
        ? (v) =>
            `${w("priority")} = ${ctx.cast("items", "priority", `(${v} #>> '{}')`)}`
        : cast("priority", "smallint"),
    },
    { field: "estimate", column: "estimate", set: cast("estimate", "numeric") },
    {
      field: "progress",
      column: "progress",
      set: cast("progress", "smallint"),
    },
    {
      field: "startAt",
      column: "startAt",
      set: cast("startAt", "timestamptz"),
    },
    { field: "endAt", column: "endAt", set: cast("endAt", "timestamptz") },
    { field: "dueAt", column: "dueAt", set: cast("dueAt", "timestamptz") },
    { field: "stageId", column: "stage", set: cast("stage", "uuid") },
    {
      field: "closeReason",
      column: "closeReason",
      set: (v) =>
        `${w("closeReason")} = ${ctx.cast("items", "closeReason", `nullif(trim(${v} #>> '{}'), '')`)}`,
    },
  ];
}

export function taskFunctions(ctx: BlockSqlContext, n: TaskNames): string {
  const { fn, t, c, e } = n;
  const w = (column: string): string => c("items", column);
  const a = (column: string): string => c("assignees", column);
  const item = sqlString(n.type);
  const itemId = sqlString(e("taskId"));
  const has = (logical: string): boolean => ctx.has("items", logical);

  const state = (value: string, labels: readonly string[], negate = false) =>
    ctx.is("items", "state", value, labels, negate);

  // A column of row, or null when the app maps it to null.
  const or = (row: string, logical: string): string =>
    has(logical) ? `${row}.${w(logical)}` : "null";

  // ", <column>" for an insert's column list, when the column exists.
  const also = (table: string, logical: string): string =>
    ctx.has(table, logical) ? `, ${c(table, logical)}` : "";

  // An items column for an insert's column list, when it exists.
  const column = (logical: string): string | undefined =>
    has(logical) ? w(logical) : undefined;

  // value when the column exists, for lines().
  const present = (
    table: string,
    logical: string,
    value: string,
  ): string | undefined => (ctx.has(table, logical) ? value : undefined);

  // The values of an insert, the present ones of each group on a line.
  const lines = (
    indent: string,
    ...groups: readonly (string | undefined)[][]
  ): string =>
    groups
      .map((group) => group.filter((value) => value !== undefined).join(", "))
      .filter((line) => line !== "")
      .join(`,\n${indent}`);

  // Refuses attrs keys of columns the app maps to null.
  const unsupported = (
    table: string,
    attrs: string,
    keys: readonly (readonly [key: string, logical: string])[],
  ): string =>
    keys
      .filter(([, logical]) => !ctx.has(table, logical))
      .map(
        ([key, logical]) => `
  if ${attrs} ->> ${sqlString(key)} is not null then
    ${fail("TASK_FIELD_UNSUPPORTED", `this ${ctx.tableName(table).name} table has no ${logical} column`, "22023")}
  end if;`,
      )
      .join("");

  const extrasInsert = insertExtraColumns(
    t("items"),
    n.extras,
    "(create_task.attrs -> 'fields')",
  );

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.write)})`;

  const row = (alias: string): string =>
    `${ctx.rowJson("items", alias, { as: { number: (v) => `${v}::text` } })} || ${int8Text(alias, [w("number")])} || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra.${a("user")} order by ${ctx.has("assignees", "createdAt") ? `ra.${a("createdAt")}, ` : ""}ra.${a("user")}) from ${t("assignees")} ra where ra.${a("item")} = ${alias}.${w("id")}), '[]'::jsonb), 'subtasks', (select jsonb_build_object('done', count(*) filter (where ${state(`ch.${w("state")}`, ["completed"])}), 'total', count(*)) from ${t("items")} ch where ch.${w("parent")} = ${alias}.${w("id")} and ch.${w("archivedAt")} is null)) || ${itemExtrasJson(ctx, n, alias)}${ctx.hasTable("claims") ? ` || jsonb_build_object('claim', ${fn("task_claim")}(${alias}.${w("id")}))` : ""}`;

  const record = (type: string, alias: string, extra = ""): string =>
    taskRecord(ctx, n, type, alias, extra);

  // A project or iteration of another tenant fails the foreign key only when
  // the id is unknown, so the write checks the tenant itself.
  const sameTenant = (
    table: "projects" | "iterations",
    idExpr: string,
    tenantExpr: string,
    hint: string,
    message: string,
  ): string =>
    ctx.hasTable(table) &&
    ctx.has("items", table === "projects" ? "project" : "iteration")
      ? `
        if ${idExpr} is not null and not exists (
          select 1 from ${t(table)} r where r.${c(table, "id")} = ${idExpr} and r.${c(table, "tenant")} = ${tenantExpr}
        ) then
          ${fail(hint, message, "P0002")}
        end if;`
      : "";

  const writes = [
    ...fields(ctx, w, e).map((field) => {
      const guard =
        field.column === "project"
          ? sameTenant(
              "projects",
              "(v_change -> 'value' #>> '{}')::uuid",
              `(select i.${w("tenant")} from ${t("items")} i where i.${w("id")} = v_item)`,
              "TASK_PROJECT_NOT_FOUND",
              "project not found",
            )
          : field.column === "iteration"
            ? sameTenant(
                "iterations",
                "(v_change -> 'value' #>> '{}')::uuid",
                `(select i.${w("tenant")} from ${t("items")} i where i.${w("id")} = v_item)`,
                "TASK_ITERATION_NOT_FOUND",
                "iteration not found",
              )
            : "";

      return has(field.column)
        ? `      when ${sqlString(field.field)} then${guard}
        update ${t("items")} x set ${field.set("v_change -> 'value'")} where x.${w("id")} = v_item;`
        : `      when ${sqlString(field.field)} then
        ${fail("TASK_FIELD_UNSUPPORTED", `this ${ctx.tableName("items").name} table has no ${field.column} column`, "22023")}`;
    }),
    has("startAt") && has("endAt")
      ? `      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          ${fail("TASK_ATTRS_INVALID", "window must be an object of startAt and endAt", "22023")}
        end if;
        update ${t("items")} x set
          ${w("startAt")} = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x.${w("startAt")} end,
          ${w("endAt")} = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x.${w("endAt")} end
        where x.${w("id")} = v_item;`
      : `      when 'window' then
        ${fail("TASK_FIELD_UNSUPPORTED", `this ${ctx.tableName("items").name} table has no startAt and endAt columns`, "22023")}`,
    `      when 'attachments' then
        select * into v_row from ${t("items")} x where x.${w("id")} = v_item;
        ${linkAttachmentsSql(ctx, n, "v_row", "(v_change -> 'value')")}`,
    ...n.extras.map(
      (extra) => `      when ${sqlString(extra.name)} then
        update ${t("items")} x set ${extra.ident} = (jsonb_populate_record(null::${t("items")}, jsonb_build_object(${sqlString(extra.name)}, v_change -> 'value'))).${extra.ident} where x.${w("id")} = v_item;`,
    ),
  ].join("\n");

  const watch = watchSql(ctx, {
    tenant: `v_row.${w("tenant")}`,
    user: "v_user",
    subjectType: item,
    subjectId: `v_row.${w("id")}::text`,
  });

  const actionPath =
    n.actionPath === ""
      ? "null"
      : `replace(replace(${sqlString(n.actionPath)}, '{id}', v_row.${w("id")}::text), '{identifier}', ${ctx.has("items", "identifier") ? `coalesce(v_row.${w("identifier")}, '')` : "''"})`;

  const notify =
    ctx.installed("notifications") && n.notify
      ? `
  if cardinality(v_new) > 0 then
    ${ctx.notify(
      `jsonb_build_object(
      'type', ${sqlString(e("task.assigned"))},
      'tenant', v_row.${w("tenant")},
      'actor', auth.uid(),
      'subject_type', ${item},
      'subject_id', v_row.${w("id")}::text,
      'subject_label', v_row.${w("title")},
      'summary', v_row.${w("title")},
      'action_path', ${actionPath},
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', ${sqlString(e("task.assigned:"))} || v_row.${w("id")}::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object(${itemId}, v_row.${w("id")})
    )`,
      { indent: "    " },
    )}
  end if;`
      : "";

  const limit =
    n.maxAssignees === 0
      ? ""
      : `
  if cardinality(v_users) > ${String(n.maxAssignees)} then
    ${fail("TASK_ASSIGNEES_LIMIT", `an item takes at most ${String(n.maxAssignees)} assignees`, "22023")}
  end if;`;

  const p = (column: string): string => c("projects", column);
  const i = (column: string): string => c("iterations", column);

  const manageGuard = (
    tenant: string,
  ): string => `if not (${n.service} or ${ctx.scope.can(tenant, n.manage)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to manage projects and iterations")}
  end if;`;

  const budgetSets = (
    [
      ["budgetAmount", "bigint"],
      ["budgetCurrency", "upper"],
      ["budgetHours", "numeric"],
    ] as const
  )
    .filter(([key]) => ctx.has("projects", key))
    .map(([key, type]) => {
      const value =
        type === "upper"
          ? `upper(upsert_project.attrs ->> '${key}')`
          : `(upsert_project.attrs ->> '${key}')::${type}`;

      return `        ${p(key)} = case when upsert_project.attrs ? '${key}' then ${value} else x.${p(key)} end,\n`;
    })
    .join("");

  const budgeted =
    ctx.has("projects", "budgetAmount") &&
    ctx.has("projects", "budgetCurrency");

  const budgetCheck = budgeted
    ? `
    if exists (
      select 1 from ${t("projects")} x
      where x.${p("id")} = v_id and x.${p("budgetAmount")} is not null and x.${p("budgetCurrency")} is null
    ) then
      ${fail("TASK_PROJECT_INVALID", "a budget amount needs a currency", "22023")}
    end if;`
    : "";

  const budgetText = ctx.has("projects", "budgetAmount")
    ? ` || jsonb_build_object(${sqlString(ctx.colName("projects", "budgetAmount"))}, x.${p("budgetAmount")}::text)`
    : "";

  const pages = taskPageSql(ctx, n, { w, a, p, has, row, budgetText, state });

  const dimensionSync = booksAccounting(ctx)
    ? `
  perform ${ctx.of("accounting").fn("accounting_sync_dimension_value")}(x.${p("tenant")}, 'project', 'Project', x.${p("id")}::text, x.${p("key")} || ' ' || x.${p("name")}, x.${p("archivedAt")} is not null)
  from ${t("projects")} x where x.${p("id")} = v_id;`
    : "";

  const claimRead = claimReadSql(ctx, n);

  const projectTypeName = sqlString(entityType(ctx.resolved, "project"));
  const iterationTypeName = sqlString(entityType(ctx.resolved, "iteration"));

  const projectEvent = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_project.${p("tenant")}, 'projectId', v_project.${p("id")}, 'subjectType', ${projectTypeName}, 'subjectId', v_project.${p("id")}::text, 'key', v_project.${p("key")}, 'name', v_project.${p("name")}${actorPayload(n)})`,
      subject: `'projects/' || v_project.${p("id")}::text`,
      tenant: `v_project.${p("tenant")}::text`,
      row: "v_project",
      audit: false,
    });

  const iterationEvent = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_iteration.${i("tenant")}, 'iterationId', v_iteration.${i("id")}, 'subjectType', ${iterationTypeName}, 'subjectId', v_iteration.${i("id")}::text, 'name', v_iteration.${i("name")}${actorPayload(n)})`,
      subject: `'iterations/' || v_iteration.${i("id")}::text`,
      tenant: `v_iteration.${i("tenant")}::text`,
      row: "v_iteration",
      audit: false,
    });

  const projectFields = [
    ["description", "description", "text"],
    ["teamId", "team", "uuid"],
    ["priority", "priority", "smallint"],
    ["icon", "icon", "text"],
    ["color", "color", "text"],
    ["rank", "rank", "text"],
    ["health", "health", "text"],
    ["healthAt", "healthAt", "timestamptz"],
    ["startResolution", "startResolution", "text"],
    ["targetResolution", "targetResolution", "text"],
    ["completedAt", "completedAt", "timestamptz"],
    ["canceledAt", "canceledAt", "timestamptz"],
  ] as const;

  const projectSets = projectFields
    .filter(([, logical]) => ctx.has("projects", logical))
    .map(
      ([key, logical, type]) =>
        `        ${p(logical)} = case when upsert_project.attrs ? '${key}' then nullif(upsert_project.attrs ->> '${key}', '')::${type} else x.${p(logical)} end,\n`,
    )
    .join("");

  const projectInsertColumns = projectFields
    .filter(([, logical]) => ctx.has("projects", logical))
    .map(([, logical]) => also("projects", logical))
    .join("");

  const projectInsertValues = projectFields
    .filter(([, logical]) => ctx.has("projects", logical))
    .map(([key, logical, type]) =>
      logical === "priority"
        ? `coalesce(nullif(upsert_project.attrs ->> 'priority', '')::smallint, 0)`
        : logical === "rank"
          ? `coalesce(nullif(upsert_project.attrs ->> 'rank', ''), 'V')`
          : `nullif(upsert_project.attrs ->> '${key}', '')::${type}`,
    );

  const projects = ctx.hasTable("projects")
    ? `
-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived, and the budget:
-- budgetAmount (minor units as text) with budgetCurrency, and budgetHours.
-- With accounting, the project is a value of the project dimension.
create or replace function ${fn("upsert_project")}(tenant ${ctx.idType}, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := upsert_project.project;
  v_created boolean := v_id is null;
  v_was timestamptz;
  v_project ${t("projects")};
begin
  ${manageGuard("upsert_project.tenant")}${unsupported(
    "projects",
    "upsert_project.attrs",
    [
      ["description", "description"],
      ["teamId", "team"],
      ["priority", "priority"],
      ["icon", "icon"],
      ["color", "color"],
      ["rank", "rank"],
      ["health", "health"],
      ["healthAt", "healthAt"],
      ["startResolution", "startResolution"],
      ["targetResolution", "targetResolution"],
      ["completedAt", "completedAt"],
      ["canceledAt", "canceledAt"],
      ["ownerId", "owner"],
      ["startOn", "startOn"],
      ["targetOn", "targetOn"],
      ["budgetAmount", "budgetAmount"],
      ["budgetCurrency", "budgetCurrency"],
      ["budgetHours", "budgetHours"],
    ],
  )}
  if not v_created then
    select x.${p("archivedAt")} into v_was from ${t("projects")} x where x.${p("id")} = v_id and x.${p("tenant")} = upsert_project.tenant;
  end if;
  begin
    if v_id is null then
      insert into ${t("projects")} (${p("tenant")}, ${p("key")}, ${p("name")}${also("projects", "owner")}${projectInsertColumns}, ${p("status")}${also("projects", "startOn")}${also("projects", "targetOn")}${also("projects", "budgetAmount")}${also("projects", "budgetCurrency")}${also("projects", "budgetHours")})
      values (${lines(
        "        ",
        [
          "upsert_project.tenant",
          "upper(upsert_project.attrs ->> 'key')",
          "upsert_project.attrs ->> 'name'",
          present(
            "projects",
            "owner",
            "(upsert_project.attrs ->> 'ownerId')::uuid",
          ),
          ...projectInsertValues,
        ],
        [
          ctx.cast(
            "projects",
            "status",
            "coalesce(upsert_project.attrs ->> 'status', 'planned')",
          ),
          present(
            "projects",
            "startOn",
            "(upsert_project.attrs ->> 'startOn')::date",
          ),
          present(
            "projects",
            "targetOn",
            "(upsert_project.attrs ->> 'targetOn')::date",
          ),
        ],
        [
          present(
            "projects",
            "budgetAmount",
            "(upsert_project.attrs ->> 'budgetAmount')::bigint",
          ),
          present(
            "projects",
            "budgetCurrency",
            "upper(upsert_project.attrs ->> 'budgetCurrency')",
          ),
          present(
            "projects",
            "budgetHours",
            "(upsert_project.attrs ->> 'budgetHours')::numeric",
          ),
        ],
      )})
      returning ${p("id")} into v_id;
    else
      update ${t("projects")} x set
        ${p("key")} = coalesce(upper(upsert_project.attrs ->> 'key'), x.${p("key")}),
        ${p("name")} = coalesce(upsert_project.attrs ->> 'name', x.${p("name")}),
${projectSets}
${ctx.has("projects", "owner") ? `        ${p("owner")} = case when upsert_project.attrs ? 'ownerId' then (upsert_project.attrs ->> 'ownerId')::uuid else x.${p("owner")} end,\n` : ""}        ${p("status")} = coalesce(${ctx.cast("projects", "status", "upsert_project.attrs ->> 'status'")}, x.${p("status")}),
${(["startOn", "targetOn"] as const).flatMap((key) => (ctx.has("projects", key) ? [`        ${p(key)} = case when upsert_project.attrs ? '${key}' then (upsert_project.attrs ->> '${key}')::date else x.${p(key)} end,\n`] : [])).join("")}${budgetSets}        ${p("archivedAt")} = case when upsert_project.attrs ? 'archived' then (case when (upsert_project.attrs ->> 'archived')::boolean then coalesce(x.${p("archivedAt")}, now()) end) else x.${p("archivedAt")} end,
        ${p("updatedAt")} = now()
      where x.${p("id")} = v_id and x.${p("tenant")} = upsert_project.tenant;
      if not found then
        ${fail("TASK_PROJECT_NOT_FOUND", "project not found", "P0002")}
      end if;
    end if;${budgetCheck}
  exception when unique_violation then
    ${fail("TASK_PROJECT_KEY_TAKEN", "another project has this key", "23505")}
  when check_violation or not_null_violation then
    ${fail("TASK_PROJECT_INVALID", "a project needs a key of capitals and a name, and ends after it starts", "22023")}
  end;
  select * into v_project from ${t("projects")} x where x.${p("id")} = v_id;
  if v_created then
    ${projectEvent("project.created")}
  else
    ${projectEvent("project.updated")}
    if v_project.${p("archivedAt")} is not null and v_was is null then
      ${projectEvent("project.archived")}
    elsif v_project.${p("archivedAt")} is null and v_was is not null then
      ${projectEvent("project.restored")}
    end if;
  end if;
${dimensionSync}
  return (select ${ctx.rowJson("projects", "x")}${budgetText} || jsonb_build_object('progress', ${
    has("project")
      ? projectProgressSql(
          t("items"),
          w("project"),
          `x.${p("id")}`,
          w("archivedAt"),
          state,
          `y.${w("state")}`,
        )
      : "null"
  }) from ${t("projects")} x where x.${p("id")} = v_id);
end;
$$;
${userGrant(`${fn("upsert_project")}(${ctx.idType}, uuid, jsonb)`)}

-- Archives a project, or brings it back when archived is false.
create or replace function ${fn("archive_project")}(project uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project ${t("projects")};
  v_was timestamptz;
begin
  select x.${p("archivedAt")} into v_was from ${t("projects")} x where x.${p("id")} = archive_project.project;
  update ${t("projects")} x set
    ${p("archivedAt")} = case when archive_project.archived then coalesce(x.${p("archivedAt")}, now()) end,
    ${p("updatedAt")} = now()
  where x.${p("id")} = archive_project.project and (${n.service} or ${ctx.scope.can(`x.${p("tenant")}`, n.manage)})
  returning * into v_project;
  if v_project.${p("id")} is null then
    return false;
  end if;
  ${projectEvent("project.updated")}
  if archive_project.archived and v_was is null then
    ${projectEvent("project.archived")}
  elsif not archive_project.archived and v_was is not null then
    ${projectEvent("project.restored")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("archive_project")}(uuid, boolean)`)}

-- Deletes a project that is already archived and unlinks its tasks.
create or replace function ${fn("remove_project")}(project uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project ${t("projects")};
begin
  select * into v_project from ${t("projects")} x
  where x.${p("id")} = remove_project.project and x.${p("archivedAt")} is not null
    and (${n.service} or ${ctx.scope.can(`x.${p("tenant")}`, n.manage)});
  if v_project.${p("id")} is null then
    return false;
  end if;
  ${has("project") ? `update ${t("items")} y set ${w("project")} = null where y.${w("project")} = v_project.${p("id")};` : ""}
  delete from ${t("projects")} x where x.${p("id")} = v_project.${p("id")};
  ${projectEvent("project.deleted")}
  return true;
end;
$$;
${userGrant(`${fn("remove_project")}(uuid)`)}

${pages.projects}
`
    : "";

  const iterations = ctx.hasTable("iterations")
    ? `
-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function ${fn("upsert_iteration")}(tenant ${ctx.idType}, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := upsert_iteration.iteration;
  v_created boolean := v_id is null;
  v_iteration ${t("iterations")};
begin
  ${manageGuard("upsert_iteration.tenant")}${unsupported("iterations", "upsert_iteration.attrs", [["teamId", "team"]])}
  begin
    if v_id is null then
      insert into ${t("iterations")} (${i("tenant")}${also("iterations", "team")}, ${i("name")}, ${i("startsOn")}, ${i("endsOn")})
      values (upsert_iteration.tenant, ${ctx.has("iterations", "team") ? "(upsert_iteration.attrs ->> 'teamId')::uuid, " : ""}upsert_iteration.attrs ->> 'name',
        (upsert_iteration.attrs ->> 'startsOn')::date, (upsert_iteration.attrs ->> 'endsOn')::date)
      returning ${i("id")} into v_id;
    else
      update ${t("iterations")} x set
        ${i("name")} = coalesce(upsert_iteration.attrs ->> 'name', x.${i("name")}),
${ctx.has("iterations", "team") ? `        ${i("team")} = case when upsert_iteration.attrs ? 'teamId' then (upsert_iteration.attrs ->> 'teamId')::uuid else x.${i("team")} end,\n` : ""}        ${i("startsOn")} = coalesce((upsert_iteration.attrs ->> 'startsOn')::date, x.${i("startsOn")}),
        ${i("endsOn")} = coalesce((upsert_iteration.attrs ->> 'endsOn')::date, x.${i("endsOn")})
      where x.${i("id")} = v_id and x.${i("tenant")} = upsert_iteration.tenant;
      if not found then
        ${fail("TASK_ITERATION_NOT_FOUND", "iteration not found", "P0002")}
      end if;
    end if;
  exception when check_violation or not_null_violation then
    ${fail("TASK_ITERATION_INVALID", "an iteration needs a name and ends on or after it starts", "22023")}
  end;
  select * into v_iteration from ${t("iterations")} x where x.${i("id")} = v_id;
  if v_created then
    ${iterationEvent("iteration.created")}
  else
    ${iterationEvent("iteration.updated")}
  end if;
  return (select ${ctx.rowJson("iterations", "x")} from ${t("iterations")} x where x.${i("id")} = v_id);
end;
$$;
${userGrant(`${fn("upsert_iteration")}(${ctx.idType}, uuid, jsonb)`)}

-- Iterations of a tenant, soonest first. filters: teamId, limit.
create or replace function ${fn("page_iterations")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.starts_on, p.id), '[]'::jsonb)
  from (
    select ${ctx.rowJson("iterations", "x")} as value, x.${i("startsOn")} as starts_on, x.${i("id")} as id
    from ${t("iterations")} x
    where x.${i("tenant")} = page_iterations.tenant
      and (${ctx.has("iterations", "team") ? `(page_iterations.filters ->> 'teamId' is null or x.${i("team")} = (page_iterations.filters ->> 'teamId')::uuid)` : "page_iterations.filters ->> 'teamId' is null"})
    order by x.${i("startsOn")}, x.${i("id")}
    limit ${pageSize("(page_iterations.filters ->> 'limit')::integer", 50, 200)}
  ) p
$$;
${userGrant(`${fn("page_iterations")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("get_iteration")}(iteration uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${ctx.rowJson("iterations", "x")} || jsonb_build_object(
    'status', case
      when x.${i("endsOn")} < current_date then 'completed'
      when x.${i("startsOn")} > current_date then 'upcoming'
      else 'active'
    end,
    'capacity', ${
      ctx.has("items", "estimate") && ctx.has("items", "iteration")
        ? `(
      select round(avg(done)) from (
        select sum(t.${c("items", "estimate")}) filter (where t.${c("items", "state")} = 'completed') as done
        from ${t("iterations")} prev
        join ${t("items")} t on t.${c("items", "iteration")} = prev.${i("id")}
        where prev.${i("tenant")} = x.${i("tenant")} and prev.${i("endsOn")} < x.${i("startsOn")}
        group by prev.${i("id")}
        order by prev.${i("endsOn")} desc
        limit 3
      ) recent
    )`
        : "null"
    }
  ) from ${t("iterations")} x where x.${i("id")} = get_iteration.iteration
$$;
${userGrant(`${fn("get_iteration")}(uuid)`)}

create or replace function ${fn("remove_iteration")}(iteration uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_iteration ${t("iterations")};
begin
  delete from ${t("iterations")} x
  where x.${i("id")} = remove_iteration.iteration
    and (${n.service} or ${ctx.scope.can(`x.${i("tenant")}`, n.manage)})
  returning * into v_iteration;
  if v_iteration.${i("id")} is null then
    return false;
  end if;
  ${iterationEvent("iteration.deleted")}
  return true;
end;
$$;
${userGrant(`${fn("remove_iteration")}(uuid)`)}
`
    : "";

  return `${claimRead}
-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none, 1 low, 2 medium, 3 high, 4 urgent), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function ${fn("create_task")}(tenant ${ctx.idType}, attrs jsonb, assignees uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row ${t("items")};
  v_linked integer;
begin
  if not (${n.service} or ${ctx.scope.can("create_task.tenant", n.create)}) then
    ${fail("TASK_FORBIDDEN", "not allowed to change work items")}
  end if;
  if nullif(trim(create_task.attrs ->> 'title'), '') is null then
    ${fail("TASK_TITLE_REQUIRED", "a title is required", "23502")}
  end if;${unsupported("items", "create_task.attrs", [
    ["body", "body"],
    [e("projectId"), "project"],
    [e("iterationId"), "iteration"],
    ["estimate", "estimate"],
    ["progress", "progress"],
    ["startAt", "startAt"],
    ["endAt", "endAt"],
  ])}
  ${ctx.hook("before_task_create", [
    [ctx.idType, "create_task.tenant"],
    ["jsonb", "create_task.attrs"],
  ])}${sameTenant(
    "projects",
    `(create_task.attrs ->> ${sqlString(e("projectId"))})::uuid`,
    "create_task.tenant",
    "TASK_PROJECT_NOT_FOUND",
    "project not found",
  )}${sameTenant(
    "iterations",
    `(create_task.attrs ->> ${sqlString(e("iterationId"))})::uuid`,
    "create_task.tenant",
    "TASK_ITERATION_NOT_FOUND",
    "iteration not found",
  )}
  ${assignNumberSql(
    ctx,
    e("task"),
    "create_task.tenant",
    { seq: "v_seq", identifier: "v_identifier" },
    {
      table: t("items"),
      seq: w("number"),
      tenant: w("tenant"),
      prefix: n.prefix,
    },
    "now()",
    n.templates
      ? { when: "nullif(create_task.attrs ->> 'templateId', '') is null" }
      : {},
  )}
  ${projectIdentifierSql(ctx, n)}
  begin
    insert into ${t("items")} (${lines(
      "      ",
      [
        w("tenant"),
        w("number"),
        w("identifier"),
        w("title"),
        column("body"),
        w("parent"),
        w("team"),
        column("project"),
        column("iteration"),
      ],
      [
        w("priority"),
        column("estimate"),
        column("progress"),
        column("startAt"),
        column("endAt"),
        w("dueAt"),
        w("pipeline"),
        w("stage"),
        column("createdBy"),
      ],
    )}${extrasInsert.columns}${n.templates ? `, ${w("template")}${ctx.has("items", "sourceTemplate") ? `, ${w("sourceTemplate")}` : ""}` : ""})
    values (${lines(
      "      ",
      [
        "create_task.tenant",
        "v_seq",
        "v_identifier",
        "trim(create_task.attrs ->> 'title')",
        present("items", "body", "create_task.attrs ->> 'body'"),
      ],
      [
        "(create_task.attrs ->> 'parentId')::uuid",
        "(create_task.attrs ->> 'teamId')::uuid",
        present(
          "items",
          "project",
          `(create_task.attrs ->> ${sqlString(e("projectId"))})::uuid`,
        ),
      ],
      [
        present(
          "items",
          "iteration",
          `(create_task.attrs ->> ${sqlString(e("iterationId"))})::uuid`,
        ),
        ctx.mapsValues("items", "priority")
          ? ctx.cast(
              "items",
              "priority",
              "coalesce(create_task.attrs ->> 'priority', '0')",
            )
          : "coalesce((create_task.attrs ->> 'priority')::smallint, 0)",
      ],
      [
        present(
          "items",
          "estimate",
          "(create_task.attrs ->> 'estimate')::numeric",
        ),
        present(
          "items",
          "progress",
          "(create_task.attrs ->> 'progress')::smallint",
        ),
      ],
      [
        present(
          "items",
          "startAt",
          "(create_task.attrs ->> 'startAt')::timestamptz",
        ),
        present(
          "items",
          "endAt",
          "(create_task.attrs ->> 'endAt')::timestamptz",
        ),
        "(create_task.attrs ->> 'dueAt')::timestamptz",
      ],
      [
        "(create_task.attrs ->> 'pipelineId')::uuid",
        "(create_task.attrs ->> 'stageId')::uuid",
        present("items", "createdBy", "auth.uid()"),
      ],
    )}${extrasInsert.values}${n.templates ? `, nullif(create_task.attrs ->> 'templateId', '')::uuid${ctx.has("items", "sourceTemplate") ? ", nullif(create_task.attrs ->> 'sourceTemplateId', '')::uuid" : ""}` : ""})
    returning ${w("id")} into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    ${fail("TASK_ATTRS_INVALID", "a work item field has an invalid value", "22023")}
  end;${writeExtraColumns(t("items"), n.extras, "(create_task.attrs -> 'fields')", `x.${w("id")} = v_id`)}
  if cardinality(coalesce(create_task.assignees, '{}')) > 0 then
    perform ${fn("set_task_assignees")}(v_id, create_task.assignees);
  end if;
${
  ctx.installed("rank")
    ? `  update ${t("items")} x set ${w("rank")} = ${ctx.of("rank").fn("rank_between")}((select max(y.${w("rank")} collate "C") from ${t("items")} y where y.${w("tenant")} = x.${w("tenant")} and y.${w("stage")} is not distinct from x.${w("stage")} and y.${w("archivedAt")} is null and y.${w("id")} <> x.${w("id")}), null)
  where x.${w("id")} = v_id and x.${w("stage")} is not null;
`
    : ""
}${
    ctx.installed("relations")
      ? `  if jsonb_typeof(create_task.attrs -> 'needs') = 'array' and jsonb_array_length(create_task.attrs -> 'needs') > 0 then
    perform ${fn("set_task_needs")}(v_id, array(select x::uuid from jsonb_array_elements_text(create_task.attrs -> 'needs') x));
  end if;
`
      : ""
  }  select * into v_row from ${t("items")} x where x.${w("id")} = v_id;
  ${linkAttachmentsSql(ctx, n, "v_row", "(create_task.attrs -> 'attachments')")}
  ${record("task.created", "v_row")}
  ${ctx.hook("after_task_create", [["uuid", "v_id"]])}
  return (select ${row("x")} from ${t("items")} x where x.${w("id")} = v_id);
end;
$$;
${userGrant(`${fn("create_task")}(${ctx.idType}, jsonb, uuid[])`)}

-- Applies a batch of { taskId, field, value } changes, each on its
-- own. Returns { accepted: [{ taskId, field }], rejected: [{ taskId,
-- field, hint, reason }] }. With atomic, the first change that fails raises
-- its error and no change is kept. The window field ({ startAt, endAt })
-- writes both ends in one update, so the end-after-start check sees both.
drop function if exists ${fn("update_tasks")}(jsonb);
create or replace function ${fn("update_tasks")}(changes jsonb, atomic boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row ${t("items")};
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
  v_seen jsonb := '{}';
  v_was timestamptz;
begin
  if jsonb_typeof(coalesce(update_tasks.changes, '[]')) <> 'array' then
    ${fail("TASK_CHANGES_INVALID", `changes must be a list of { ${e("taskId")}, field, value }`, "22023")}
  end if;
  for v_change in select value from jsonb_array_elements(update_tasks.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> ${itemId})::uuid;
      if not exists (select 1 from ${t("items")} x where x.${w("id")} = v_item and ${editable("x")} and x.${w("archivedAt")} is null) then
        ${fail("TASK_NOT_FOUND", "no such work item you can edit", "P0002")}
      end if;
      -- expectedVersion is the updatedAt the caller read. Every change of the
      -- batch compares to the row as it was before the batch, which an earlier
      -- change of the same item has already moved on.
      if not v_seen ? v_item::text then
        select x.${w("updatedAt")} into v_was from ${t("items")} x where x.${w("id")} = v_item for update;
        v_seen := v_seen || jsonb_build_object(v_item::text, v_was);
      end if;
      if v_change ? 'expectedVersion' and (v_seen ->> v_item::text)::timestamptz is distinct from (v_change ->> 'expectedVersion')::timestamptz then
        ${fail(STALE_WRITE, "the work item changed since it was read", STALE_WRITE_SQLSTATE)}
      end if;
      ${ctx.hook("before_task_update", [
        ["uuid", "v_item"],
        ["text", "v_field"],
        ["jsonb", "v_change -> 'value'"],
      ])}
      case v_field
${writes}
      else
        ${fail("TASK_FIELD_UNKNOWN", "that field can't be written", "22023")}
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object(${itemId}, v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      ${ctx.hook("after_task_update", [
        ["uuid", "v_item"],
        ["text", "v_field"],
      ])}
    exception when others then
      if update_tasks.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(${itemId}, v_change ->> ${itemId}, 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from ${t("items")} x where x.${w("id")} = any (v_touched) loop
    ${record("task.updated", "v_row", `, 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> ${itemId})::uuid = v_row.${w("id")})`)}
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
${userGrant(`${fn("update_tasks")}(jsonb, boolean)`)}

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. task.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function ${fn("set_task_assignees")}(task uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_task_assignees.users, '{}')) x where x is not null);
  v_added uuid[];${notify === "" ? "" : "\n  v_new uuid[];\n  v_claims text;"}${watch === "" ? "" : "\n  v_user uuid;"}
begin
  select * into v_row from ${t("items")} x where x.${w("id")} = set_task_assignees.task and ${editable("x")};
  if v_row.${w("id")} is null then
    ${fail("TASK_NOT_FOUND", "no such work item you can edit", "P0002")}
  end if;${limit}${
    notify === ""
      ? ""
      : `
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from ${t("assignees")} y where y.${a("item")} = v_row.${w("id")} and y.${a("user")} = x));`
  }
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from ${t("assignees")} y where y.${a("item")} = v_row.${w("id")} and y.${a("user")} = x));
  delete from ${t("assignees")} y where y.${a("item")} = v_row.${w("id")} and not (y.${a("user")} = any (v_users));
  insert into ${t("assignees")} (${a("tenant")}, ${a("item")}, ${a("user")})
  select v_row.${w("tenant")}, v_row.${w("id")}, x from unnest(v_users) x
  on conflict do nothing;${
    watch === ""
      ? ""
      : `
  foreach v_user in array v_users loop
    ${watch}
  end loop;`
  }${notify}
  if cardinality(v_added) > 0 then
    ${record("task.assigned", "v_row", ", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)")}
  end if;
  return cardinality(v_users);
end;
$$;
${userGrant(`${fn("set_task_assignees")}(uuid, uuid[])`)}

create or replace function ${fn("archive_task")}(task uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_was timestamptz;
begin
  select x.${w("archivedAt")} into v_was from ${t("items")} x where x.${w("id")} = archive_task.task;
  update ${t("items")} x set ${w("archivedAt")} = case when archive_task.archived then coalesce(x.${w("archivedAt")}, now()) end
  where x.${w("id")} = archive_task.task and ${editable("x")}
  returning * into v_row;
  if v_row.${w("id")} is null then
    return false;
  end if;
  if archive_task.archived then
    ${record("task.archived", "v_row")}
  elsif v_was is not null then
    ${record("task.restored", "v_row")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("archive_task")}(uuid, boolean)`)}

-- The set form of archive_task: one update for every id, so the access check
-- runs once per statement. Returns { ids, skipped }: skipped lists the ids
-- that don't exist or that you can't edit.
create or replace function ${fn("archive_tasks")}(ids uuid[], archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_ids uuid[] := '{}';
  v_was uuid[];
begin
  select coalesce(array_agg(x.${w("id")}), '{}') into v_was from ${t("items")} x
  where x.${w("id")} = any (coalesce(archive_tasks.ids, '{}')) and x.${w("archivedAt")} is not null;
  for v_row in
    with changed as (
      update ${t("items")} x set ${w("archivedAt")} = case when archive_tasks.archived then coalesce(x.${w("archivedAt")}, now()) end
      where x.${w("id")} = any (coalesce(archive_tasks.ids, '{}')) and ${editable("x")}
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row.${w("id")});
    if archive_tasks.archived then
      ${record("task.archived", "v_row")}
    elsif v_row.${w("id")} = any (v_was) then
      ${record("task.restored", "v_row")}
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_tasks.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$$;
${userGrant(`${fn("archive_tasks")}(uuid[], boolean)`)}

-- Deletes an item and its children. Needs tasks.manage, or its author.
create or replace function ${fn("delete_task")}(task uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  delete from ${t("items")} x
  where x.${w("id")} = delete_task.task
    and (${n.service} or ${has("createdBy") && n.authorCanDelete ? `x.${w("createdBy")} = auth.uid() or` : ""} ${ctx.scope.can(`x.${w("tenant")}`, n.remove)})
  returning * into v_row;
  if v_row.${w("id")} is null then
    return false;
  end if;
  ${record("task.deleted", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("delete_task")}(uuid)`)}

-- The set form of delete_task: one delete, one access check per statement.
-- Returns { ids, skipped } like archive_tasks.
create or replace function ${fn("delete_tasks")}(ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_ids uuid[] := '{}';
begin
  for v_row in
    with removed as (
      delete from ${t("items")} x
      where x.${w("id")} = any (coalesce(delete_tasks.ids, '{}'))
        and (${n.service} or ${has("createdBy") && n.authorCanDelete ? `x.${w("createdBy")} = auth.uid() or` : ""} ${ctx.scope.can(`x.${w("tenant")}`, n.remove)})
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row.${w("id")});
    ${record("task.deleted", "v_row")}
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_tasks.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$$;
${userGrant(`${fn("delete_tasks")}(uuid[])`)}

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function ${fn("task_tree")}(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from ${t("items")} x where x.${w("id")} = task_tree.root
    union all
    select y.*, tree.depth + 1 from ${t("items")} y join tree on y.${w("parent")} = tree.${w("id")}
    where tree.depth < 100 and y.${w("archivedAt")} is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree.${w("id")}, 'parentId', tree.${w("parent")}, 'identifier', tree.${w("identifier")}, 'title', tree.${w("title")},
    'state', ${ctx.label("items", "state", `tree.${w("state")}`)}, 'startAt', ${or("tree", "startAt")}, 'endAt', ${or("tree", "endAt")}, 'dueAt', tree.${w("dueAt")},
    'locked', ${or("tree", "locked")}, 'depth', tree.depth,
    'progress', coalesce(${or("tree", "progress")}, (
      select case when count(*) filter (where ${state(`ch.${w("state")}`, ["canceled"], true)}) = 0 then
          ${ctx.mapsValues("items", "state") ? `case when ${state(`tree.${w("state")}`, ["completed"])} then 100 else 0 end` : `case tree.${w("state")} when 'completed' then 100 else 0 end`}
        else round(100.0 * count(*) filter (where ${state(`ch.${w("state")}`, ["completed"])}) / count(*) filter (where ${state(`ch.${w("state")}`, ["canceled"], true)}))::integer end
      from ${t("items")} ch where ch.${w("parent")} = tree.${w("id")} and ch.${w("archivedAt")} is null))
  ) order by tree.depth, tree.${w("rank")} collate "C", tree.${w("id")}), '[]'::jsonb)
  from tree
$$;
${userGrant(`${fn("task_tree")}(uuid)`)}

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function ${fn("list_tasks")}(tenant ${ctx.idType}, filter jsonb, search text, after uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.number desc), '[]'::jsonb)
  from (
    select ${row("x")} as value, x.${w("number")} as number
    from ${t("items")} x
    where x.${w("tenant")} = list_tasks.tenant and x.${w("archivedAt")} is null${n.templates ? `\n      and (case coalesce(list_tasks.filter ->> 'templates', 'exclude') when 'include' then true when 'only' then x.${w("template")} is not null else x.${w("template")} is null end)` : ""}
      and (list_tasks.filter ->> 'teamId' is null or x.${w("team")} = (list_tasks.filter ->> 'teamId')::uuid)
      and (list_tasks.filter ->> ${sqlString(e("projectId"))} is null or ${has("project") ? `x.${w("project")} = (list_tasks.filter ->> ${sqlString(e("projectId"))})::uuid` : "false"})
      and (list_tasks.filter ->> ${sqlString(e("iterationId"))} is null or ${has("iteration") ? `x.${w("iteration")} = (list_tasks.filter ->> ${sqlString(e("iterationId"))})::uuid` : "false"})
      and (list_tasks.filter ->> 'parentId' is null or x.${w("parent")} = (list_tasks.filter ->> 'parentId')::uuid)
      and (list_tasks.filter ->> 'assigneeId' is null or exists (select 1 from ${t("assignees")} y where y.${a("item")} = x.${w("id")} and y.${a("user")} = (list_tasks.filter ->> 'assigneeId')::uuid))
      and (list_tasks.filter -> 'states' is null or ${ctx.mapsValues("items", "state") ? ctx.label("items", "state", `x.${w("state")}`) : asText(ctx, "items", `x.${w("state")}`)} = any (array(select jsonb_array_elements_text(list_tasks.filter -> 'states'))))
      and (coalesce((list_tasks.filter ->> 'open')::boolean, false) = false or x.${w("closedAt")} is null)${has("waitingOn") ? `\n      and (coalesce((list_tasks.filter ->> 'ready')::boolean, false) = false or (x.${w("waitingOn")} = 0 and x.${w("closedAt")} is null))` : ""}
      and (list_tasks.search is null or x.${w("title")} ilike '%' || list_tasks.search || '%' or x.${w("identifier")} ilike list_tasks.search || '%')
      and (list_tasks.after is null or x.${w("number")} < (select z.${w("number")} from ${t("items")} z where z.${w("id")} = list_tasks.after))
    order by x.${w("number")} desc
    limit ${pageSize("list_tasks.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("list_tasks")}(${ctx.idType}, jsonb, text, uuid, integer)`)}

${pages.tasks}
${cloneTask(ctx, n, fn, t, w, a, row)}${taskExtraFunctions(ctx, n, row, record)}${projects}${iterations}
${coordinationSql(ctx, n, { row })}`;
}

/**
 * Copies a task and its assignees, checklist and child tasks. A template copy
 * is a live task (numbered, with events) unless overrides.templateId is set.
 */
function cloneTask(
  ctx: BlockSqlContext,
  n: TaskNames,
  fn: (name: string) => string,
  t: (table: string) => string,
  w: (column: string) => string,
  a: (column: string) => string,
  row: (alias: string) => string,
): string {
  const owned = n.templates
    ? `exists (with recursive up as (select x.${w("id")}, x.${w("parent")}, x.${w("template")} from ${t("items")} x where x.${w("id")} = v_src.${w("id")} union all select p.${w("id")}, p.${w("parent")}, p.${w("template")} from ${t("items")} p join up on p.${w("id")} = up.${w("parent")}) select 1 from up where up.${w("template")} is not null)`
    : "false";

  const template = n.templates
    ? `case when coalesce(clone_task.overrides, '{}'::jsonb) ? 'templateId' then clone_task.overrides ->> 'templateId' else null end`
    : "null";

  const source = n.templates
    ? `case when v_src.${w("template")} is not null then v_src.${w("template")}::text else v_src.${ctx.has("items", "sourceTemplate") ? w("sourceTemplate") : "id"}::text end`
    : "null";

  const tags =
    ctx.installed("tags") && ctx.of("tags").hasTable("taggings")
      ? `
  insert into ${ctx.of("tags").table("taggings")} (${ctx.of("tags").col("taggings", "tenant")}, ${ctx.of("tags").col("taggings", "tag")}, ${ctx.of("tags").col("taggings", "subjectType")}, ${ctx.of("tags").col("taggings", "subjectId")})
  select v_tenant, g.${ctx.of("tags").col("taggings", "tag")}, g.${ctx.of("tags").col("taggings", "subjectType")}, v_id::text
  from ${ctx.of("tags").table("taggings")} g
  where g.${ctx.of("tags").col("taggings", "subjectType")} = ${sqlString(n.type)} and g.${ctx.of("tags").col("taggings", "subjectId")} = clone_task.source::text;`
      : "";

  const checklist = ctx.hasTable("checklist")
    ? `
  insert into ${t("checklist")} (${ctx.col("checklist", "tenant")}, ${ctx.col("checklist", "item")}, ${ctx.col("checklist", "title")}, ${ctx.col("checklist", "done")}, ${ctx.col("checklist", "rank")})
  select v_tenant, v_id, c.${ctx.col("checklist", "title")}, false, c.${ctx.col("checklist", "rank")}
  from ${t("checklist")} c where c.${ctx.col("checklist", "item")} = clone_task.source;`
    : "";

  return `
-- Copies source into a new task. overrides replaces the fields the caller
-- edited. A template becomes a live task unless overrides.templateId is set.
create or replace function ${fn("clone_task")}(source uuid, overrides jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src ${t("items")}%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
  v_tenant ${ctx.idType};
begin
  select * into v_src from ${t("items")} x where x.${w("id")} = clone_task.source;
  if not found then
    ${fail("TASK_NOT_FOUND", "no such work item", "P0002")}
  end if;
  ${cloneTenant(ctx, { fn: "clone_task", code: "TASK_FORBIDDEN", source: "v_src", tenant: w("tenant"), owned, service: n.service, can: n.create, message: "not allowed to change work items" })}
  ${ctx.hook("before_task_clone", [
    ["uuid", "clone_task.source"],
    ["jsonb", "clone_task.overrides"],
  ])}
  select coalesce(array_agg(ra.${a("user")}), '{}') into v_users from ${t("assignees")} ra where ra.${a("item")} = v_src.${w("id")};
  v_created := ${fn("create_task")}(v_tenant, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src.${w("title")},
    'body', ${ctx.has("items", "body") ? `v_src.${w("body")}` : "null"},
    'parentId', v_src.${w("parent")},
    'teamId', v_src.${w("team")},
    'projectId', ${ctx.has("items", "project") ? `v_src.${w("project")}` : "null"},
    'iterationId', ${ctx.has("items", "iteration") ? `v_src.${w("iteration")}` : "null"},
    'estimate', ${ctx.has("items", "estimate") ? `v_src.${w("estimate")}` : "null"},
    'progress', ${ctx.has("items", "progress") ? `v_src.${w("progress")}` : "null"},
    'startAt', ${ctx.has("items", "startAt") ? `v_src.${w("startAt")}` : "null"},
    'endAt', ${ctx.has("items", "endAt") ? `v_src.${w("endAt")}` : "null"},
    'dueAt', v_src.${w("dueAt")},
    'priority', v_src.${w("priority")},
    'templateId', ${template},
    'sourceTemplateId', ${source}
  )) || (coalesce(clone_task.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', ${template}, 'sourceTemplateId', ${source})), v_users);
  v_id := (v_created ->> 'id')::uuid;${checklist}${tags}
  for v_child in select c.${w("id")} from ${t("items")} c where c.${w("parent")} = clone_task.source loop
    v_copy := ${fn("clone_task")}(v_child, coalesce(clone_task.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update ${t("items")} x set ${w("parent")} = v_id where x.${w("id")} = (v_copy ->> 'id')::uuid;
  end loop;
  ${ctx.hook("after_task_clone", [["uuid", "v_id"]])}
  return (select ${row("x")} from ${t("items")} x where x.${w("id")} = v_id);
end;
$$;
${userGrant(`${fn("clone_task")}(uuid, jsonb)`)}
${projectWorkFunctions(ctx, n)}
`;
}
