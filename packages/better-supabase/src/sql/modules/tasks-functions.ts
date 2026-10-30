import type { ExtraColumn, BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { int8Text } from "../money-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import {
  fail,
  insertExtraColumns,
  pageSize,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { watchSql } from "../watch-sql.ts";
import { asText } from "./over-app.ts";
import {
  itemExtrasJson,
  linkAttachmentsSql,
  workItemExtraFunctions,
} from "./tasks-extras.ts";

export interface WorkItemNames {
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
   * `options.extraColumns`: create writes them from attrs.fields, update by
   * name.
   */
  readonly extras: readonly ExtraColumn[];
  /**
   * An entity name, event type or payload key after `blocks.tasks.names`:
   * `work_item` to `task`, `projectId` to `initiativeId`.
   */
  readonly e: (name: string) => string;
}

/**
 * The fields `update_work_items` writes, by camelCase name, with the logical
 * column each one writes.
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

export function workItemFunctions(
  ctx: BlockSqlContext,
  n: WorkItemNames,
): string {
  const { fn, t, c, e } = n;
  const w = (column: string): string => c("items", column);
  const a = (column: string): string => c("assignees", column);
  const item = sqlString(e("work_item"));
  const itemId = sqlString(e("workItemId"));
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
    ${fail("WORK_ITEM_FIELD_UNSUPPORTED", `this ${ctx.tableName(table).name} table has no ${logical} column`, "22023")}
  end if;`,
      )
      .join("");

  const extrasInsert = insertExtraColumns(
    t("items"),
    n.extras,
    "(create_work_item.attrs -> 'fields')",
  );

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.write)})`;

  const row = (alias: string): string =>
    `${ctx.rowJson("items", alias, { as: { number: (v) => `${v}::text` } })} || ${int8Text(alias, [w("number")])} || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra.${a("user")} order by ${ctx.has("assignees", "createdAt") ? `ra.${a("createdAt")}, ` : ""}ra.${a("user")}) from ${t("assignees")} ra where ra.${a("item")} = ${alias}.${w("id")}), '[]'::jsonb)) || ${itemExtrasJson(ctx, n, alias)}`;

  const record = (type: string, alias: string, extra = ""): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${alias}.${w("tenant")}, 'workItemId', ${alias}.${w("id")}, 'subjectType', ${item}, 'subjectId', ${alias}.${w("id")}::text, 'title', ${alias}.${w("title")}${extra})`,
      subject: `'work-items/' || ${alias}.${w("id")}::text`,
      tenant: `${alias}.${w("tenant")}::text`,
      audit: false,
    });

  const writes = [
    ...fields(ctx, w, e).map((field) =>
      has(field.column)
        ? `      when ${sqlString(field.field)} then
        update ${t("items")} x set ${field.set("v_change -> 'value'")} where x.${w("id")} = v_item;`
        : `      when ${sqlString(field.field)} then
        ${fail("WORK_ITEM_FIELD_UNSUPPORTED", `this ${ctx.tableName("items").name} table has no ${field.column} column`, "22023")}`,
    ),
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
      'type', ${sqlString(e("work_item.assigned"))},
      'tenant', v_row.${w("tenant")},
      'actor', auth.uid(),
      'subject_type', ${item},
      'subject_id', v_row.${w("id")}::text,
      'subject_label', v_row.${w("title")},
      'summary', v_row.${w("title")},
      'action_path', ${actionPath},
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', ${sqlString(e("work_item.assigned:"))} || v_row.${w("id")}::text || ':' || md5(array_to_string(v_new, ',')),
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
    ${fail("WORK_ITEM_ASSIGNEES_LIMIT", `an item takes at most ${String(n.maxAssignees)} assignees`, "22023")}
  end if;`;

  const p = (column: string): string => c("projects", column);
  const i = (column: string): string => c("iterations", column);

  const manageGuard = (
    tenant: string,
  ): string => `if not (${n.service} or ${ctx.scope.can(tenant, n.manage)}) then
    ${fail("WORK_ITEM_FORBIDDEN", "not allowed to manage projects and iterations")}
  end if;`;

  const projects = ctx.hasTable("projects")
    ? `
-- Creates a project (project null) or changes the keys attrs names: key,
-- name, ownerId, status, startOn, targetOn, archived.
create or replace function ${fn("save_project")}(tenant ${ctx.idType}, project uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_project.project;
begin
  ${manageGuard("save_project.tenant")}${unsupported(
    "projects",
    "save_project.attrs",
    [
      ["ownerId", "owner"],
      ["startOn", "startOn"],
      ["targetOn", "targetOn"],
    ],
  )}
  begin
    if v_id is null then
      insert into ${t("projects")} (${p("tenant")}, ${p("key")}, ${p("name")}${also("projects", "owner")}, ${p("status")}${also("projects", "startOn")}${also("projects", "targetOn")})
      values (${lines(
        "        ",
        [
          "save_project.tenant",
          "upper(save_project.attrs ->> 'key')",
          "save_project.attrs ->> 'name'",
          present(
            "projects",
            "owner",
            "(save_project.attrs ->> 'ownerId')::uuid",
          ),
        ],
        [
          ctx.cast(
            "projects",
            "status",
            "coalesce(save_project.attrs ->> 'status', 'planned')",
          ),
          present(
            "projects",
            "startOn",
            "(save_project.attrs ->> 'startOn')::date",
          ),
          present(
            "projects",
            "targetOn",
            "(save_project.attrs ->> 'targetOn')::date",
          ),
        ],
      )})
      returning ${p("id")} into v_id;
    else
      update ${t("projects")} x set
        ${p("key")} = coalesce(upper(save_project.attrs ->> 'key'), x.${p("key")}),
        ${p("name")} = coalesce(save_project.attrs ->> 'name', x.${p("name")}),
${ctx.has("projects", "owner") ? `        ${p("owner")} = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x.${p("owner")} end,\n` : ""}        ${p("status")} = coalesce(${ctx.cast("projects", "status", "save_project.attrs ->> 'status'")}, x.${p("status")}),
${(["startOn", "targetOn"] as const).flatMap((key) => (ctx.has("projects", key) ? [`        ${p(key)} = case when save_project.attrs ? '${key}' then (save_project.attrs ->> '${key}')::date else x.${p(key)} end,\n`] : [])).join("")}        ${p("archivedAt")} = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x.${p("archivedAt")}, now()) end) else x.${p("archivedAt")} end,
        ${p("updatedAt")} = now()
      where x.${p("id")} = v_id and x.${p("tenant")} = save_project.tenant;
      if not found then
        ${fail("WORK_ITEM_PROJECT_NOT_FOUND", "project not found", "P0002")}
      end if;
    end if;
  exception when unique_violation then
    ${fail("WORK_ITEM_PROJECT_KEY_TAKEN", "another project has this key", "23505")}
  when check_violation or not_null_violation then
    ${fail("WORK_ITEM_PROJECT_INVALID", "a project needs a key of capitals and a name, and ends after it starts", "22023")}
  end;
  return (select ${ctx.rowJson("projects", "x")} || jsonb_build_object('progress', ${
    has("project")
      ? `(
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where ${state(`y.${w("state")}`, ["completed"])}) / count(*) filter (where ${state(`y.${w("state")}`, ["canceled"], true)})) end
      from ${t("items")} y where y.${w("project")} = x.${p("id")} and y.${w("archivedAt")} is null
    )`
      : "null"
  }) from ${t("projects")} x where x.${p("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_project")}(${ctx.idType}, uuid, jsonb)`)}
`
    : "";

  const iterations = ctx.hasTable("iterations")
    ? `
-- Creates an iteration (a cycle or a sprint) or changes it: name, teamId,
-- startsOn, endsOn.
create or replace function ${fn("save_iteration")}(tenant ${ctx.idType}, iteration uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_iteration.iteration;
begin
  ${manageGuard("save_iteration.tenant")}${unsupported("iterations", "save_iteration.attrs", [["teamId", "team"]])}
  begin
    if v_id is null then
      insert into ${t("iterations")} (${i("tenant")}${also("iterations", "team")}, ${i("name")}, ${i("startsOn")}, ${i("endsOn")})
      values (save_iteration.tenant, ${ctx.has("iterations", "team") ? "(save_iteration.attrs ->> 'teamId')::uuid, " : ""}save_iteration.attrs ->> 'name',
        (save_iteration.attrs ->> 'startsOn')::date, (save_iteration.attrs ->> 'endsOn')::date)
      returning ${i("id")} into v_id;
    else
      update ${t("iterations")} x set
        ${i("name")} = coalesce(save_iteration.attrs ->> 'name', x.${i("name")}),
        ${i("startsOn")} = coalesce((save_iteration.attrs ->> 'startsOn')::date, x.${i("startsOn")}),
        ${i("endsOn")} = coalesce((save_iteration.attrs ->> 'endsOn')::date, x.${i("endsOn")})
      where x.${i("id")} = v_id and x.${i("tenant")} = save_iteration.tenant;
      if not found then
        ${fail("WORK_ITEM_ITERATION_NOT_FOUND", "iteration not found", "P0002")}
      end if;
    end if;
  exception when check_violation or not_null_violation then
    ${fail("WORK_ITEM_ITERATION_INVALID", "an iteration needs a name and ends on or after it starts", "22023")}
  end;
  return (select ${ctx.rowJson("iterations", "x")} from ${t("iterations")} x where x.${i("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_iteration")}(${ctx.idType}, uuid, jsonb)`)}
`
    : "";

  return `
-- Creates a work item. attrs: title (required), body, parentId, teamId,
-- projectId, iterationId, priority (0 none to 4 low, as Linear), estimate,
-- progress, startAt, endAt, dueAt, pipelineId, stageId, and fields (the
-- extra columns, by name). assignees: user ids.
create or replace function ${fn("create_work_item")}(tenant ${ctx.idType}, attrs jsonb, assignees uuid[])
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
  if not (${n.service} or ${ctx.scope.can("create_work_item.tenant", n.create)}) then
    ${fail("WORK_ITEM_FORBIDDEN", "not allowed to change work items")}
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    ${fail("WORK_ITEM_TITLE_REQUIRED", "a title is required", "23502")}
  end if;${unsupported("items", "create_work_item.attrs", [
    ["body", "body"],
    [e("projectId"), "project"],
    [e("iterationId"), "iteration"],
    ["estimate", "estimate"],
    ["progress", "progress"],
    ["startAt", "startAt"],
    ["endAt", "endAt"],
  ])}
  ${ctx.hook("before_work_item_create", [
    [ctx.idType, "create_work_item.tenant"],
    ["jsonb", "create_work_item.attrs"],
  ])}
  ${assignNumberSql(
    ctx,
    e("work_item"),
    "create_work_item.tenant",
    { seq: "v_seq", identifier: "v_identifier" },
    {
      table: t("items"),
      seq: w("number"),
      tenant: w("tenant"),
      prefix: n.prefix,
    },
  )}
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
    )}${extrasInsert.columns})
    values (${lines(
      "      ",
      [
        "create_work_item.tenant",
        "v_seq",
        "v_identifier",
        "trim(create_work_item.attrs ->> 'title')",
        present("items", "body", "create_work_item.attrs ->> 'body'"),
      ],
      [
        "(create_work_item.attrs ->> 'parentId')::uuid",
        "(create_work_item.attrs ->> 'teamId')::uuid",
        present(
          "items",
          "project",
          `(create_work_item.attrs ->> ${sqlString(e("projectId"))})::uuid`,
        ),
      ],
      [
        present(
          "items",
          "iteration",
          `(create_work_item.attrs ->> ${sqlString(e("iterationId"))})::uuid`,
        ),
        ctx.mapsValues("items", "priority")
          ? ctx.cast(
              "items",
              "priority",
              "coalesce(create_work_item.attrs ->> 'priority', '0')",
            )
          : "coalesce((create_work_item.attrs ->> 'priority')::smallint, 0)",
      ],
      [
        present(
          "items",
          "estimate",
          "(create_work_item.attrs ->> 'estimate')::numeric",
        ),
        present(
          "items",
          "progress",
          "(create_work_item.attrs ->> 'progress')::smallint",
        ),
      ],
      [
        present(
          "items",
          "startAt",
          "(create_work_item.attrs ->> 'startAt')::timestamptz",
        ),
        present(
          "items",
          "endAt",
          "(create_work_item.attrs ->> 'endAt')::timestamptz",
        ),
        "(create_work_item.attrs ->> 'dueAt')::timestamptz",
      ],
      [
        "(create_work_item.attrs ->> 'pipelineId')::uuid",
        "(create_work_item.attrs ->> 'stageId')::uuid",
        present("items", "createdBy", "auth.uid()"),
      ],
    )}${extrasInsert.values})
    returning ${w("id")} into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    ${fail("WORK_ITEM_ATTRS_INVALID", "a work item field has an invalid value", "22023")}
  end;${writeExtraColumns(t("items"), n.extras, "(create_work_item.attrs -> 'fields')", `x.${w("id")} = v_id`)}
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform ${fn("set_work_item_assignees")}(v_id, create_work_item.assignees);
  end if;
  select * into v_row from ${t("items")} x where x.${w("id")} = v_id;
  ${linkAttachmentsSql(ctx, n, "v_row", "(create_work_item.attrs -> 'attachments')")}
  ${record("work_item.created", "v_row")}
  ${ctx.hook("after_work_item_create", [["uuid", "v_id"]])}
  return (select ${row("x")} from ${t("items")} x where x.${w("id")} = v_id);
end;
$$;
${userGrant(`${fn("create_work_item")}(${ctx.idType}, jsonb, uuid[])`)}

-- Applies a batch of { workItemId, field, value } changes, each on its
-- own. Returns { accepted: [{ workItemId, field }], rejected: [{ workItemId,
-- field, hint, reason }] }.
create or replace function ${fn("update_work_items")}(changes jsonb)
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
begin
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    ${fail("WORK_ITEM_CHANGES_INVALID", `changes must be a list of { ${e("workItemId")}, field, value }`, "22023")}
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> ${itemId})::uuid;
      if not exists (select 1 from ${t("items")} x where x.${w("id")} = v_item and ${editable("x")} and x.${w("archivedAt")} is null) then
        ${fail("WORK_ITEM_NOT_FOUND", "no such work item you can edit", "P0002")}
      end if;
      ${ctx.hook("before_work_item_update", [
        ["uuid", "v_item"],
        ["text", "v_field"],
        ["jsonb", "v_change -> 'value'"],
      ])}
      case v_field
${writes}
      else
        ${fail("WORK_ITEM_FIELD_UNKNOWN", "that field can't be written", "22023")}
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object(${itemId}, v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      ${ctx.hook("after_work_item_update", [
        ["uuid", "v_item"],
        ["text", "v_field"],
      ])}
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(${itemId}, v_change ->> ${itemId}, 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from ${t("items")} x where x.${w("id")} = any (v_touched) loop
    ${record("work_item.updated", "v_row", `, 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> ${itemId})::uuid = v_row.${w("id")})`)}
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
${userGrant(`${fn("update_work_items")}(jsonb)`)}

-- Replaces an item's assignees. Each one watches the item, and those who
-- weren't assigned before are notified. work_item.assigned is recorded only
-- when the call adds someone, with addedIds.
create or replace function ${fn("set_work_item_assignees")}(work_item uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_added uuid[];${notify === "" ? "" : "\n  v_new uuid[];\n  v_claims text;"}${watch === "" ? "" : "\n  v_user uuid;"}
begin
  select * into v_row from ${t("items")} x where x.${w("id")} = set_work_item_assignees.work_item and ${editable("x")};
  if v_row.${w("id")} is null then
    ${fail("WORK_ITEM_NOT_FOUND", "no such work item you can edit", "P0002")}
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
    ${record("work_item.assigned", "v_row", ", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)")}
  end if;
  return cardinality(v_users);
end;
$$;
${userGrant(`${fn("set_work_item_assignees")}(uuid, uuid[])`)}

create or replace function ${fn("archive_work_item")}(work_item uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  update ${t("items")} x set ${w("archivedAt")} = case when archive_work_item.archived then coalesce(x.${w("archivedAt")}, now()) end
  where x.${w("id")} = archive_work_item.work_item and ${editable("x")}
  returning * into v_row;
  if v_row.${w("id")} is null then
    return false;
  end if;
  if archive_work_item.archived then
    ${record("work_item.archived", "v_row")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("archive_work_item")}(uuid, boolean)`)}

-- Deletes an item and its children. Needs work_items.manage, or its author.
create or replace function ${fn("delete_work_item")}(work_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  delete from ${t("items")} x
  where x.${w("id")} = delete_work_item.work_item
    and (${n.service} or ${has("createdBy") && n.authorCanDelete ? `x.${w("createdBy")} = auth.uid() or` : ""} ${ctx.scope.can(`x.${w("tenant")}`, n.remove)})
  returning * into v_row;
  if v_row.${w("id")} is null then
    return false;
  end if;
  ${record("work_item.deleted", "v_row")}
  return true;
end;
$$;
${userGrant(`${fn("delete_work_item")}(uuid)`)}

-- An item and everything under it with its depth. An item without its own
-- progress takes the share of its open and completed children that are
-- completed, so a Gantt group shows a rollup.
create or replace function ${fn("work_item_tree")}(root uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive tree as (
    select x.*, 0 as depth from ${t("items")} x where x.${w("id")} = work_item_tree.root
    union all
    select y.*, tree.depth + 1 from ${t("items")} y join tree on y.${w("parent")} = tree.${w("id")}
    where tree.depth < 100 and y.${w("archivedAt")} is null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tree.${w("id")}, 'parentId', tree.${w("parent")}, 'identifier', tree.${w("identifier")}, 'title', tree.${w("title")},
    'state', ${ctx.label("items", "state", `tree.${w("state")}`)}, 'startAt', ${or("tree", "startAt")}, 'endAt', ${or("tree", "endAt")}, 'dueAt', tree.${w("dueAt")},
    'locked', tree.${w("locked")}, 'depth', tree.depth,
    'progress', coalesce(${or("tree", "progress")}, (
      select case when count(*) filter (where ${state(`ch.${w("state")}`, ["canceled"], true)}) = 0 then
          ${ctx.mapsValues("items", "state") ? `case when ${state(`tree.${w("state")}`, ["completed"])} then 100 else 0 end` : `case tree.${w("state")} when 'completed' then 100 else 0 end`}
        else round(100.0 * count(*) filter (where ${state(`ch.${w("state")}`, ["completed"])}) / count(*) filter (where ${state(`ch.${w("state")}`, ["canceled"], true)}))::integer end
      from ${t("items")} ch where ch.${w("parent")} = tree.${w("id")} and ch.${w("archivedAt")} is null))
  ) order by tree.depth, tree.${w("rank")} collate "C", tree.${w("id")}), '[]'::jsonb)
  from tree
$$;
${userGrant(`${fn("work_item_tree")}(uuid)`)}

-- A page of a tenant's active items, newest first. filter keys: teamId,
-- projectId, iterationId, parentId, assigneeId, states (a list), open
-- (only unclosed). search matches the title and identifier. after continues
-- after that item.
create or replace function ${fn("list_work_items")}(tenant ${ctx.idType}, filter jsonb, search text, after uuid, page_size integer)
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
    where x.${w("tenant")} = list_work_items.tenant and x.${w("archivedAt")} is null
      and (list_work_items.filter ->> 'teamId' is null or x.${w("team")} = (list_work_items.filter ->> 'teamId')::uuid)
      and (list_work_items.filter ->> ${sqlString(e("projectId"))} is null or ${has("project") ? `x.${w("project")} = (list_work_items.filter ->> ${sqlString(e("projectId"))})::uuid` : "false"})
      and (list_work_items.filter ->> ${sqlString(e("iterationId"))} is null or ${has("iteration") ? `x.${w("iteration")} = (list_work_items.filter ->> ${sqlString(e("iterationId"))})::uuid` : "false"})
      and (list_work_items.filter ->> 'parentId' is null or x.${w("parent")} = (list_work_items.filter ->> 'parentId')::uuid)
      and (list_work_items.filter ->> 'assigneeId' is null or exists (select 1 from ${t("assignees")} y where y.${a("item")} = x.${w("id")} and y.${a("user")} = (list_work_items.filter ->> 'assigneeId')::uuid))
      and (list_work_items.filter -> 'states' is null or ${ctx.mapsValues("items", "state") ? ctx.label("items", "state", `x.${w("state")}`) : asText(ctx, "items", `x.${w("state")}`)} = any (array(select jsonb_array_elements_text(list_work_items.filter -> 'states'))))
      and (coalesce((list_work_items.filter ->> 'open')::boolean, false) = false or x.${w("closedAt")} is null)
      and (list_work_items.search is null or x.${w("title")} ilike '%' || list_work_items.search || '%' or x.${w("identifier")} ilike list_work_items.search || '%')
      and (list_work_items.after is null or x.${w("number")} < (select z.${w("number")} from ${t("items")} z where z.${w("id")} = list_work_items.after))
    order by x.${w("number")} desc
    limit ${pageSize("list_work_items.page_size", 50, 200)}
  ) p
$$;
${userGrant(`${fn("list_work_items")}(${ctx.idType}, jsonb, text, uuid, integer)`)}
${workItemExtraFunctions(ctx, n, row, record)}${projects}${iterations}`;
}
