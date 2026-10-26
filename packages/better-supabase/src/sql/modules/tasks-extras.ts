import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { WorkItemNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { columnsObject, fail, serviceGrant, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/**
 * The reminders rule table a work item's recurrence lives in, when it has one
 * and the items table has the column that links a repeat to its source.
 */
function recurrenceRules(
  ctx: BlockSqlContext,
):
  | { readonly table: string; readonly col: (column: string) => string }
  | undefined {
  const r = ctx.installed("reminders") ? ctx.of("reminders") : undefined;

  if (
    r === undefined ||
    r.mode === "custom" ||
    !r.has("rules", "rrule") ||
    !ctx.has("items", "recursFrom")
  ) {
    return;
  }

  return {
    table: r.table("rules"),
    col: (column: string): string => r.col("rules", column),
  };
}

function watchable(ctx: BlockSqlContext): boolean {
  return (
    ctx.installed("notifications") &&
    ctx.of("notifications").hasTable("subscriptions")
  );
}

function attachable(ctx: BlockSqlContext): boolean {
  return (
    ctx.installed("attachments") && ctx.of("attachments").mode !== "custom"
  );
}

/**
 * The checklist table, with its read policy; empty when the module doesn't
 * manage tables.
 */
export function checklistTable(ctx: BlockSqlContext, n: WorkItemNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const k = (column: string): string => c("checklist", column);
  const w = (column: string): string => c("items", column);

  // A column definition, left out when the app maps the column to null.
  const column = (
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has("checklist", logical) ? `\n  ${definition(k(logical))},` : "";

  const recurs = ctx.has("items", "recursFrom")
    ? `
alter table ${t("items")} add column if not exists ${w("recursFrom")} uuid references ${t("items")} (${w("id")}) on delete set null;
create unique index if not exists ${ctx.naming.rename("work_items_recurs_from_idx")} on ${t("items")} (${w("recursFrom")});`
    : "";

  if (!ctx.hasTable("checklist")) {
    return `${recurs}
`;
  }

  const name = ctx.tableName("checklist").name;

  return `${recurs}

create table if not exists ${t("checklist")} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("item")} uuid not null references ${t("items")} (${w("id")}) on delete cascade,
  ${k("title")} text not null check (length(${k("title")}) between 1 and 500),
  ${k("done")} boolean not null default false,${column("doneAt", (name) => `${name} timestamptz`)}${column("doneBy", (name) => `${name} uuid`)}
  ${k("rank")} text collate "C" not null check (${k("rank")} ~ ${RANK_KEY_PATTERN}),${column("createdBy", (name) => `${name} uuid`)}
  ${k("createdAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("work_item_checklist_item_idx")} on ${t("checklist")} (${k("item")}, ${k("rank")});
${lockModuleTable(ctx, "checklist", { read: true })}
${renderPolicy(makePolicy({ table: t("checklist"), name: `${name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(k("tenant"), n.read) }), { drop: true, target: t("checklist") })}
`;
}

/**
 * The keys `row()` adds to a work item: `checklist` ({ total, done }) and, with
 * reminders, `recurrence` ({ rrule, tzid, dtstart } or null).
 */
export function itemExtrasJson(
  ctx: BlockSqlContext,
  n: WorkItemNames,
  alias: string,
): string {
  const k = (column: string): string => n.c("checklist", column);
  const w = (column: string): string => n.c("items", column);
  const rules = recurrenceRules(ctx);

  const recurrence =
    rules === undefined
      ? ""
      : `, 'recurrence', (select jsonb_build_object('rrule', rr.${rules.col("rrule")}, 'tzid', rr.${rules.col("tzid")}, 'dtstart', rr.${rules.col("dtstart")}) from ${rules.table} rr where rr.${rules.col("tenant")} = ${alias}.${w("tenant")} and rr.${rules.col("subjectType")} = ${sqlString(n.e("work_item"))} and rr.${rules.col("subjectId")} = ${alias}.${w("id")}::text)`;

  const checklist = ctx.hasTable("checklist")
    ? `(select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk.${k("done")})) from ${n.t("checklist")} rk where rk.${k("item")} = ${alias}.${w("id")})`
    : "null";

  return `jsonb_build_object('checklist', ${checklist}${recurrence})`;
}

/**
 * PL/pgSQL that links the caller's own attachments without a subject (`ids`, a
 * jsonb list) to item `alias`. Empty without attachments.
 */
export function linkAttachmentsSql(
  ctx: BlockSqlContext,
  n: WorkItemNames,
  alias: string,
  ids: string,
): string {
  if (!attachable(ctx)) {
    return `if jsonb_array_length(coalesce(${ids}, '[]'::jsonb)) > 0 then
      ${fail("WORK_ITEM_ATTACHMENTS_UNAVAILABLE", "install the attachments block to attach files", "0A000")}
    end if;`;
  }

  const at = ctx.of("attachments");
  const f = (column: string): string => at.col("attachments", column);
  const w = (column: string): string => n.c("items", column);
  const path = at.text("path", "{organization_id}/attachments/{id}");

  if (path.includes("{subject_")) {
    return `if jsonb_array_length(coalesce(${ids}, '[]'::jsonb)) > 0 then
      ${fail("WORK_ITEM_ATTACHMENTS_PATH", "the attachments path names the subject, so a file can't move onto an item", "0A000")}
    end if;`;
  }

  return `if jsonb_typeof(coalesce(${ids}, '[]'::jsonb)) <> 'array' then
      ${fail("WORK_ITEM_ATTACHMENTS_INVALID", "attachments must be a list of attachment ids", "22023")}
    end if;
    if jsonb_array_length(coalesce(${ids}, '[]'::jsonb)) > 0 then
      update ${at.table("attachments")} f set ${f("subjectType")} = ${sqlString(n.e("work_item"))}, ${f("subjectId")} = ${alias}.${w("id")}::text
      where f.${f("id")} = any (array(select jsonb_array_elements_text(${ids})::uuid))
        and f.${f("tenant")} = ${alias}.${w("tenant")}
        and (f.${f("subjectType")} is null or (f.${f("subjectType")} = ${sqlString(n.e("work_item"))} and f.${f("subjectId")} = ${alias}.${w("id")}::text))
        and (${n.service} or f.${f("uploadedBy")} = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text(${ids}) x) then
        ${fail("WORK_ITEM_ATTACHMENTS_INVALID", "attach only your own files in this organization that aren't on another subject", "22023")}
      end if;
    end if;`;
}

/** The checklist, recurrence, watcher and read functions of the tasks module. */
export function workItemExtraFunctions(
  ctx: BlockSqlContext,
  n: WorkItemNames,
  row: (alias: string) => string,
  record: (type: string, alias: string, extra?: string) => string,
): string {
  const { fn, t, c, e } = n;
  const w = (column: string): string => c("items", column);
  const k = (column: string): string => c("checklist", column);

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.write)})`;

  const readable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.read)})`;

  const notFound = fail(
    "WORK_ITEM_NOT_FOUND",
    "no such work item you can edit",
    "P0002",
  );

  // A column of row, or null when the app maps it to null.
  const or = (table: string, row: string, logical: string): string =>
    ctx.has(table, logical) ? `${row}.${c(table, logical)}` : "null";

  // ", <column>" for an insert's column list, when the column exists.
  const also = (table: string, logical: string): string =>
    ctx.has(table, logical) ? `, ${c(table, logical)}` : "";

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

  // A set clause line of an update, for a column that exists.
  const set = (table: string, logical: string, value: string): string =>
    `,\n        ${c(table, logical)} = ${value}`;

  const touched = (field: string): string =>
    record(
      "work_item.updated",
      "v_row",
      `, 'fields', jsonb_build_array(${sqlString(field)})`,
    );

  const checklistRow = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${k("id")}, ${sqlString(e("workItemId"))}, ${alias}.${k("item")}, 'title', ${alias}.${k("title")}, 'done', ${alias}.${k("done")}, 'doneAt', ${or("checklist", alias, "doneAt")}, 'doneBy', ${or("checklist", alias, "doneBy")}, 'rank', ${alias}.${k("rank")}, 'createdAt', ${alias}.${k("createdAt")})`;

  const checklist = `
-- Adds a checklist item (checklist_item null) or changes one: title, done,
-- rank. A new item without a rank goes last.
create or replace function ${fn("save_work_item_checklist_item")}(work_item uuid, checklist_item uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
  v_id uuid := save_work_item_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_work_item_checklist_item.attrs ->> 'done')::boolean;
begin
  select * into v_row from ${t("items")} x where x.${w("id")} = save_work_item_checklist_item.work_item and ${editable("x")} and x.${w("archivedAt")} is null;
  if v_row.${w("id")} is null then
    ${notFound}
  end if;
  begin
    if v_id is null then
      select max(y.${k("rank")}) into v_last from ${t("checklist")} y where y.${k("item")} = v_row.${w("id")};
      insert into ${t("checklist")} (${k("tenant")}, ${k("item")}, ${k("title")}, ${k("done")}${also("checklist", "doneAt")}${also("checklist", "doneBy")}, ${k("rank")}${also("checklist", "createdBy")})
      values (${lines(
        "        ",
        [
          `v_row.${w("tenant")}`,
          `v_row.${w("id")}`,
          "trim(save_work_item_checklist_item.attrs ->> 'title')",
          "coalesce(v_done, false)",
        ],
        [
          present("checklist", "doneAt", "case when v_done then now() end"),
          present(
            "checklist",
            "doneBy",
            "case when v_done then auth.uid() end",
          ),
        ],
        [
          `coalesce(save_work_item_checklist_item.attrs ->> 'rank', ${rankAfter("v_last")})`,
          present("checklist", "createdBy", "auth.uid()"),
        ],
      )})
      returning ${k("id")} into v_id;
    else
      update ${t("checklist")} y set
        ${k("title")} = coalesce(trim(save_work_item_checklist_item.attrs ->> 'title'), y.${k("title")}),
        ${k("rank")} = coalesce(save_work_item_checklist_item.attrs ->> 'rank', y.${k("rank")}),
        ${k("done")} = coalesce(v_done, y.${k("done")})${ctx.has("checklist", "doneAt") ? set("checklist", "doneAt", `case when v_done is null then y.${k("doneAt")} when v_done then coalesce(y.${k("doneAt")}, now()) end`) : ""}${ctx.has("checklist", "doneBy") ? set("checklist", "doneBy", `case when v_done is null then y.${k("doneBy")} when v_done then coalesce(y.${k("doneBy")}, auth.uid()) end`) : ""}
      where y.${k("id")} = v_id and y.${k("item")} = v_row.${w("id")};
      if not found then
        ${fail("WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND", "no such checklist item on this work item", "P0002")}
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    ${fail("WORK_ITEM_CHECKLIST_ITEM_INVALID", "a checklist item needs a title of 1 to 500 characters and a valid rank", "22023")}
  end;
  ${touched("checklist")}
  return (select ${checklistRow("y")} from ${t("checklist")} y where y.${k("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_work_item_checklist_item")}(uuid, uuid, jsonb)`)}

create or replace function ${fn("delete_work_item_checklist_item")}(checklist_item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  select x.* into v_row from ${t("items")} x join ${t("checklist")} y on y.${k("item")} = x.${w("id")}
  where y.${k("id")} = delete_work_item_checklist_item.checklist_item and ${editable("x")} and x.${w("archivedAt")} is null;
  if v_row.${w("id")} is null then
    return false;
  end if;
  delete from ${t("checklist")} y where y.${k("id")} = delete_work_item_checklist_item.checklist_item;
  ${touched("checklist")}
  return true;
end;
$$;
${userGrant(`${fn("delete_work_item_checklist_item")}(uuid)`)}

-- An item's checklist, in rank order.
create or replace function ${fn("list_work_item_checklist")}(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${checklistRow("y")} order by y.${k("rank")} collate "C", y.${k("id")}), '[]'::jsonb)
  from ${t("checklist")} y where y.${k("item")} = list_work_item_checklist.work_item
$$;
${userGrant(`${fn("list_work_item_checklist")}(uuid)`)}
`;

  const getWorkItem = `
-- One item the caller can read, or null.
create or replace function ${fn("get_work_item")}(work_item uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${row("x")} from ${t("items")} x where x.${w("id")} = get_work_item.work_item
$$;
${userGrant(`${fn("get_work_item")}(uuid)`)}
`;

  return `${ctx.hasTable("checklist") ? checklist : ""}${getWorkItem}${recurrence(ctx, n, { row, record, editable, notFound, touched })}${watchers(ctx, n, readable)}`;
}

function recurrence(
  ctx: BlockSqlContext,
  n: WorkItemNames,
  helpers: {
    readonly row: (alias: string) => string;
    readonly record: (type: string, alias: string, extra?: string) => string;
    readonly editable: (alias: string) => string;
    readonly notFound: string;
    readonly touched: (field: string) => string;
  },
): string {
  const rules = recurrenceRules(ctx);

  if (rules === undefined) {
    return "";
  }

  const { fn, t, c, e } = n;
  const w = (column: string): string => c("items", column);
  const k = (column: string): string => c("checklist", column);
  const r = rules.col;
  const item = sqlString(e("work_item"));

  // A column of v_src, or null when the app maps it to null.
  const src = (logical: string): string =>
    ctx.has("items", logical) ? `v_src.${w(logical)}` : "null";

  const anchor = ["dueAt", "endAt", "startAt"]
    .filter((logical) => ctx.has("items", logical))
    .map((logical) => `v_src.${w(logical)}`)
    .join(", ");

  const fields =
    n.extras.length === 0
      ? ""
      : ` || jsonb_build_object('fields', ${columnsObject(
          "v_src",
          n.extras.map((extra) => extra.name),
        )})`;

  return `
-- Makes an item repeat: rrule is an RFC 5545 RRULE starting at the item's
-- due date (now without one) in tzid. A null rrule stops it. Completing the
-- item then creates the next one through repeat_work_item.
create or replace function ${fn("set_work_item_recurrence")}(work_item uuid, rrule text, tzid text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  select * into v_row from ${t("items")} x where x.${w("id")} = set_work_item_recurrence.work_item and ${helpers.editable("x")} and x.${w("archivedAt")} is null;
  if v_row.${w("id")} is null then
    ${helpers.notFound}
  end if;
  if set_work_item_recurrence.rrule is null then
    delete from ${rules.table} rr where rr.${r("tenant")} = v_row.${w("tenant")} and rr.${r("subjectType")} = ${item} and rr.${r("subjectId")} = v_row.${w("id")}::text;
  else
    if set_work_item_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      ${fail("WORK_ITEM_RECURRENCE_INVALID", "rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO", "22023")}
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_work_item_recurrence.tzid, 'UTC')) then
      ${fail("WORK_ITEM_RECURRENCE_INVALID", "tzid must be an IANA time zone", "22023")}
    end if;
    insert into ${rules.table} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("dtstart")}, ${r("tzid")}, ${r("rrule")})
    values (v_row.${w("tenant")}, ${item}, v_row.${w("id")}::text, coalesce(v_row.${w("dueAt")}, now()), coalesce(set_work_item_recurrence.tzid, 'UTC'), regexp_replace(set_work_item_recurrence.rrule, '^RRULE:', ''))
    on conflict (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")})
    do update set ${r("dtstart")} = excluded.${r("dtstart")}, ${r("tzid")} = excluded.${r("tzid")}, ${r("rrule")} = excluded.${r("rrule")};
  end if;
  ${helpers.touched("recurrence")}
  return (select ${helpers.row("x")} -> 'recurrence' from ${t("items")} x where x.${w("id")} = v_row.${w("id")});
end;
$$;
${userGrant(`${fn("set_work_item_recurrence")}(uuid, text, text)`)}

-- Creates the next item of a repeating item, due at due_at: a copy with its
-- dates shifted, its assignees and an unchecked checklist. The rule moves to
-- the copy. Runs once per item; a second call returns the same copy.
create or replace function ${fn("repeat_work_item")}(work_item uuid, due_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src ${t("items")};
  v_next jsonb;
  v_id uuid;
  v_shift interval;
begin
  select * into v_src from ${t("items")} x where x.${w("id")} = repeat_work_item.work_item for update;
  if v_src.${w("id")} is null then
    ${fail("WORK_ITEM_NOT_FOUND", "work item not found", "P0002")}
  end if;
  select x.${w("id")} into v_id from ${t("items")} x where x.${w("recursFrom")} = v_src.${w("id")};
  if v_id is not null then
    return (select ${helpers.row("x")} from ${t("items")} x where x.${w("id")} = v_id);
  end if;
  v_shift := coalesce(repeat_work_item.due_at - coalesce(${anchor}), interval '0');
  v_next := ${n.fn("create_work_item")}(v_src.${w("tenant")}, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src.${w("title")}, 'body', ${src("body")}, 'parentId', v_src.${w("parent")}, 'teamId', v_src.${w("team")},
    ${sqlString(e("projectId"))}, ${src("project")}, 'priority', v_src.${w("priority")}, 'estimate', ${src("estimate")},
    'startAt', ${src("startAt")} + v_shift, 'endAt', ${src("endAt")} + v_shift, 'dueAt', repeat_work_item.due_at,
    'pipelineId', v_src.${w("pipeline")}))${fields},
    array(select y.${c("assignees", "user")} from ${t("assignees")} y where y.${c("assignees", "item")} = v_src.${w("id")}));
  v_id := (v_next ->> 'id')::uuid;
  update ${t("items")} x set ${w("recursFrom")} = v_src.${w("id")} where x.${w("id")} = v_id;
${
  ctx.hasTable("checklist")
    ? `  insert into ${t("checklist")} (${k("tenant")}, ${k("item")}, ${k("title")}, ${k("rank")}${ctx.has("checklist", "createdBy") ? `, ${k("createdBy")}` : ""})
  select y.${k("tenant")}, v_id, y.${k("title")}, y.${k("rank")}${ctx.has("checklist", "createdBy") ? `, y.${k("createdBy")}` : ""} from ${t("checklist")} y where y.${k("item")} = v_src.${w("id")};
`
    : ""
}  update ${rules.table} rr set ${r("subjectId")} = v_id::text
  where rr.${r("tenant")} = v_src.${w("tenant")} and rr.${r("subjectType")} = ${item} and rr.${r("subjectId")} = v_src.${w("id")}::text;
  return (select ${helpers.row("x")} from ${t("items")} x where x.${w("id")} = v_id);
end;
$$;
${serviceGrant(`${fn("repeat_work_item")}(uuid, timestamptz)`)}
`;
}

function watchers(
  ctx: BlockSqlContext,
  n: WorkItemNames,
  readable: (alias: string) => string,
): string {
  if (!watchable(ctx)) {
    return "";
  }

  const { fn, t, c, e } = n;
  const w = (column: string): string => c("items", column);
  const notifications = ctx.of("notifications");

  const s = (column: string): string =>
    notifications.col("subscriptions", column);

  const item = sqlString(e("work_item"));

  const tenanted = notifications.has("subscriptions", "tenant")
    ? `\n    and s.${s("tenant")} = x.${w("tenant")}`
    : "";

  return `
-- Watches (all), follows (participating) or ignores an item the caller can
-- read; a null level removes the choice.
create or replace function ${fn("watch_work_item")}(work_item uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("items")};
begin
  select * into v_row from ${t("items")} x where x.${w("id")} = watch_work_item.work_item and ${readable("x")};
  if v_row.${w("id")} is null then
    ${fail("WORK_ITEM_NOT_FOUND", "no such work item you can read", "P0002")}
  end if;
  perform ${notifications.fn("set_notification_subscription")}(${item}, v_row.${w("id")}::text, watch_work_item.level, v_row.${w("tenant")});
  return watch_work_item.level is not null;
end;
$$;
${userGrant(`${fn("watch_work_item")}(uuid, text)`)}

-- Who watches (all) or follows (participating) an item: [{ userId, level }].
create or replace function ${fn("list_work_item_watchers")}(work_item uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', s.${s("user")}, 'level', s.${s("level")}) order by s.${s("level")}, s.${s("user")}), '[]'::jsonb)
  from ${t("items")} x
  join ${notifications.table("subscriptions")} s on s.${s("subjectType")} = ${item} and s.${s("subjectId")} = x.${w("id")}::text${tenanted}
  where x.${w("id")} = list_work_item_watchers.work_item and ${readable("x")} and s.${s("level")} in ('all', 'participating')
$$;
${userGrant(`${fn("list_work_item_watchers")}(uuid)`)}
`;
}

/** The contract entries for the functions above. */
export function workItemExtrasContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    ...(ctx.hasTable("checklist")
      ? [
          {
            name: "save_work_item_checklist_item",
            args: ["uuid", "uuid", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "delete_work_item_checklist_item",
            args: ["uuid"],
            returns: "boolean",
          },
          {
            name: "list_work_item_checklist",
            args: ["uuid"],
            returns: "jsonb",
          },
        ]
      : []),
    { name: "get_work_item", args: ["uuid"], returns: "jsonb" },
    ...(recurrenceRules(ctx) === undefined
      ? []
      : [
          {
            name: "set_work_item_recurrence",
            args: ["uuid", "text", "text"],
            returns: "jsonb",
          },
          {
            name: "repeat_work_item",
            args: ["uuid", "timestamptz"],
            returns: "jsonb",
          },
        ]),
    ...(watchable(ctx)
      ? [
          {
            name: "watch_work_item",
            args: ["uuid", "text"],
            returns: "boolean",
          },
          { name: "list_work_item_watchers", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
  ];
}
