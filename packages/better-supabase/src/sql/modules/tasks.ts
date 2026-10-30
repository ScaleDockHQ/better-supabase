import type { TasksEvents } from "../../blocks/tasks/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { WorkItemNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  schemaPreamble,
  triggerGrant,
} from "../shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";
import { myWorkTenant } from "./subjects.ts";
import { checklistTable, workItemExtrasContract } from "./tasks-extras.ts";
import { workItemFunctions } from "./tasks-functions.ts";

/** The subject type of a work item, after `blocks.tasks.names`. */
export function workItemType(tasks: BlockSqlContext): string {
  return tasks.resolved.entities["work_item"]?.to.singular ?? "work_item";
}

const ITEM = [
  "organizationId",
  "workItemId",
  "subjectType",
  "subjectId",
  "title",
] as const;

const EVENTS: BlockSqlEvents<TasksEvents> = {
  "work_item.created": { subject: "work-items", payload: [...ITEM] },
  "work_item.updated": { subject: "work-items", payload: [...ITEM, "fields"] },
  "work_item.assigned": {
    subject: "work-items",
    payload: [...ITEM, "assigneeIds", "addedIds"],
  },
  "work_item.closed": {
    subject: "work-items",
    payload: [...ITEM, "state", "closeReason"],
  },
  "work_item.reopened": { subject: "work-items", payload: [...ITEM] },
  "work_item.archived": { subject: "work-items", payload: [...ITEM] },
  "work_item.deleted": { subject: "work-items", payload: [...ITEM] },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  entities: {
    work_item: {
      table: "items",
      singular: "work_item",
      primary: true,
      subject: {
        title: "title",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "write" },
        rank: { column: "rank", group: "stage" },
        search: { title: "title", body: ["identifier", "body"] },
      },
    },
    project: { table: "projects", singular: "project" },
    iteration: { table: "iterations", singular: "iteration" },
    checklist_item: { table: "checklist", singular: "checklist_item" },
  },
  hooks: [
    "before_work_item_create",
    "after_work_item_create",
    "before_work_item_update",
    "after_work_item_update",
  ],
  options: [
    "prefix",
    "maxAssignees",
    "extraColumns",
    "authorCanDelete",
    "notify",
    "actionPath",
  ],
  tables: {
    items: {
      name: "work_items",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        identifier: "identifier",
        title: "title",
        body: "body",
        parent: "parent_id",
        team: "team_id",
        project: "project_id",
        iteration: "iteration_id",
        priority: "priority",
        estimate: "estimate",
        progress: "progress",
        startAt: "start_at",
        endAt: "end_at",
        dueAt: "due_at",
        pipeline: "pipeline_id",
        stage: "stage_id",
        stageEnteredAt: "stage_entered_at",
        state: "state",
        closeReason: "close_reason",
        closedAt: "closed_at",
        locked: "locked",
        rank: "rank",
        archivedAt: "archived_at",
        recursFrom: "recurs_from",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "body",
        "project",
        "iteration",
        "estimate",
        "progress",
        "startAt",
        "endAt",
        "recursFrom",
        "createdBy",
      ],
      typed: ["state", "closeReason"],
      mappable: ["priority"],
    },
    checklist: {
      name: "work_item_checklist_items",
      app: {},
      optionalTable: true,
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        item: "work_item_id",
        title: "title",
        done: "done",
        doneAt: "done_at",
        doneBy: "done_by",
        rank: "rank",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["doneAt", "doneBy", "createdBy"],
    },
    assignees: {
      name: "work_item_assignees",
      app: {},
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        tenant: "tenant_id",
        item: "work_item_id",
        user: "user_id",
        createdAt: "created_at",
      },
      optional: ["createdAt"],
    },
    projects: {
      name: "projects",
      optionalTable: true,
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        owner: "owner_user_id",
        status: "status",
        startOn: "start_on",
        targetOn: "target_on",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["owner", "startOn", "targetOn"],
      typed: ["status"],
    },
    iterations: {
      name: "iterations",
      optionalTable: true,
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        team: "team_id",
        name: "name",
        startsOn: "starts_on",
        endsOn: "ends_on",
        createdAt: "created_at",
      },
      optional: ["team"],
    },
  },
};

function tables(ctx: BlockSqlContext, n: WorkItemNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = n;
  const w = (column: string): string => c("items", column);
  const a = (column: string): string => c("assignees", column);

  const read = (table: string): string =>
    renderPolicy(
      makePolicy({
        table: t(table),
        name: `${ctx.tableName(table).name}_read`,
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(c(table, "tenant"), n.read),
      }),
      { drop: true, target: t(table) },
    );

  const p = (column: string): string => c("projects", column);
  const i = (column: string): string => c("iterations", column);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical) ? `\n  ${definition(c(table, logical))},` : "";

  const both = (table: string, first: string, second: string): boolean =>
    ctx.has(table, first) && ctx.has(table, second);

  const projects = ctx.hasTable("projects")
    ? `
create table if not exists ${t("projects")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("key")} text not null check (${p("key")} ~ '^[A-Z][A-Z0-9]{0,9}$'),
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),${column("projects", "owner", (name) => `${name} uuid`)}
  ${p("status")} text not null default 'planned' check (${p("status")} in ('planned', 'active', 'paused', 'completed', 'canceled')),${column("projects", "startOn", (name) => `${name} date`)}${column("projects", "targetOn", (name) => `${name} date`)}
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("key")})${both("projects", "startOn", "targetOn") ? `,\n  check (${p("targetOn")} is null or ${p("startOn")} is null or ${p("targetOn")} >= ${p("startOn")})` : ""}
);${appUniqueIndex(ctx, "projects", ["tenant", "key"])}
${lockModuleTable(ctx, "projects", { read: true })}
${read("projects")}
`
    : "";

  const iterations = ctx.hasTable("iterations")
    ? `
create table if not exists ${t("iterations")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,${column("iterations", "team", (name) => `${name} uuid`)}
  ${i("name")} text not null check (length(${i("name")}) between 1 and 200),
  ${i("startsOn")} date not null,
  ${i("endsOn")} date not null,
  ${i("createdAt")} timestamptz not null default now(),
  check (${i("endsOn")} >= ${i("startsOn")})
);
create index if not exists ${ctx.naming.rename("iterations_tenant_idx")} on ${t("iterations")} (${[i("tenant"), ...(ctx.has("iterations", "team") ? [i("team")] : []), i("startsOn")].join(", ")});
${lockModuleTable(ctx, "iterations", { read: true })}
${read("iterations")}
`
    : "";

  return `${projects}${iterations}
create table if not exists ${t("items")} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  ${w("number")} bigint not null,
  ${w("identifier")} text not null,
  ${w("title")} text not null check (length(${w("title")}) between 1 and 500),${column("items", "body", (name) => `${name} text`)}
  ${w("parent")} uuid references ${t("items")} (${w("id")}) on delete cascade,
  ${w("team")} uuid,${column("items", "project", (name) => `${name} uuid${ctx.hasTable("projects") ? ` references ${t("projects")} (${p("id")}) on delete set null` : ""}`)}${column("items", "iteration", (name) => `${name} uuid${ctx.hasTable("iterations") ? ` references ${t("iterations")} (${i("id")}) on delete set null` : ""}`)}
  ${w("priority")} smallint not null default 0 check (${w("priority")} between 0 and 4),${column("items", "estimate", (name) => `${name} numeric(10, 2) check (${name} >= 0)`)}${column("items", "progress", (name) => `${name} smallint check (${name} between 0 and 100)`)}${column("items", "startAt", (name) => `${name} timestamptz`)}${column("items", "endAt", (name) => `${name} timestamptz`)}
  ${w("dueAt")} timestamptz,
  ${w("pipeline")} uuid,
  ${w("stage")} uuid,
  ${w("stageEnteredAt")} timestamptz,
  ${w("state")} text not null default 'backlog' check (${w("state")} in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  ${w("closeReason")} text check (${w("closeReason")} in ('completed', 'not_planned', 'duplicate')),
  ${w("closedAt")} timestamptz,
  ${w("locked")} boolean not null default false,
  ${w("rank")} text collate "C" not null default 'V',
  ${w("archivedAt")} timestamptz,${column("items", "createdBy", (name) => `${name} uuid`)}
  ${w("createdAt")} timestamptz not null default now(),
  ${w("updatedAt")} timestamptz not null default now(),
  unique (${w("tenant")}, ${w("number")})${both("items", "startAt", "endAt") ? `,\n  check (${w("endAt")} is null or ${w("startAt")} is null or ${w("endAt")} >= ${w("startAt")})` : ""}
);${appUniqueIndex(ctx, "items", ["tenant", "number"])}
create index if not exists ${ctx.naming.rename("work_items_board_idx")} on ${t("items")} (${w("pipeline")}, ${w("stage")}, ${w("rank")});
create index if not exists ${ctx.naming.rename("work_items_parent_idx")} on ${t("items")} (${w("parent")});${ctx.has("items", "project") ? `\ncreate index if not exists ${ctx.naming.rename("work_items_project_idx")} on ${t("items")} (${w("project")});` : ""}${ctx.has("items", "iteration") ? `\ncreate index if not exists ${ctx.naming.rename("work_items_iteration_idx")} on ${t("items")} (${w("iteration")});` : ""}
create index if not exists ${ctx.naming.rename("work_items_due_idx")} on ${t("items")} (${w("tenant")}, ${w("dueAt")}) where ${w("closedAt")} is null;${addExtraColumns(t("items"), ctx.extraColumns("items", ["fields"]))}
${lockModuleTable(ctx, "items", { read: true })}
${read("items")}

create table if not exists ${t("assignees")} (
  ${a("tenant")} ${ctx.idType} not null,
  ${a("item")} uuid not null references ${t("items")} (${w("id")}) on delete cascade,
  ${a("user")} uuid not null,${column("assignees", "createdAt", (name) => `${name} timestamptz not null default now()`)}
  primary key (${a("item")}, ${a("user")})
);${appUniqueIndex(ctx, "assignees", ["item", "user"])}
create index if not exists ${ctx.naming.rename("work_item_assignees_user_idx")} on ${t("assignees")} (${a("user")});
${lockModuleTable(ctx, "assignees", { read: true })}
${read("assignees")}
${checklistTable(ctx, n)}`;
}

/**
 * The guard trigger: no parent cycles, a locked item keeps its dates, a closing
 * state stamps closed_at and a close reason and records work_item.closed, and
 * reopening clears both.
 */
function guard(ctx: BlockSqlContext, n: WorkItemNames): string {
  const { t, c } = n;
  const w = (column: string): string => c("items", column);
  const guardName = ctx.naming.rename("bsb_work_item_guard");

  const payload = (extra: string): string =>
    `jsonb_build_object('organizationId', new.${w("tenant")}, 'workItemId', new.${w("id")}, 'subjectType', ${sqlString(n.e("work_item"))}, 'subjectId', new.${w("id")}::text, 'title', new.${w("title")}${extra})`;

  const subject = `'work-items/' || new.${w("id")}::text`;
  const tenant = `new.${w("tenant")}::text`;

  const state = (value: string, labels: readonly string[], negate = false) =>
    ctx.is("items", "state", value, labels, negate);

  const closed = state(`new.${w("state")}`, ["completed", "canceled"]);

  const reason = ctx.cast(
    "items",
    "closeReason",
    ctx.mapsValues("items", "state")
      ? `case when ${state(`new.${w("state")}`, ["completed"])} then 'completed' else 'not_planned' end`
      : `case new.${w("state")} when 'completed' then 'completed' else 'not_planned' end`,
  );

  const dates = ["startAt", "endAt", "dueAt"]
    .filter((logical) => ctx.has("items", logical))
    .map((logical) => w(logical))
    .map((column) => `new.${column} is distinct from old.${column}`)
    .join(" or ");

  return `
create or replace function better_supabase.${guardName}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${w("parent")} is not null and (tg_op = 'INSERT' or new.${w("parent")} is distinct from old.${w("parent")}) then
    if exists (
      with recursive up(id, depth) as (
        select new.${w("parent")}, 1
        union all
        select x.${w("parent")}, up.depth + 1 from ${t("items")} x join up on x.${w("id")} = up.id
        where x.${w("parent")} is not null and up.depth < 100
      )
      select 1 from up where up.id = new.${w("id")}
    ) then
      ${fail("WORK_ITEM_PARENT_CYCLE", "an item can't sit under itself", "23514")}
    end if;
    if not exists (select 1 from ${t("items")} x where x.${w("id")} = new.${w("parent")} and x.${w("tenant")} = new.${w("tenant")}) then
      ${fail("WORK_ITEM_PARENT_INVALID", "the parent is in another organization", "22023")}
    end if;
  end if;
  if tg_op = 'UPDATE' and old.${w("locked")} and not ${n.service} and (${dates}) then
    ${fail("WORK_ITEM_LOCKED", "the item is locked; its dates can't change", "55000")}
  end if;
  if tg_op = 'INSERT' then
    if ${closed} then
      new.${w("closedAt")} := now();
      new.${w("closeReason")} := coalesce(new.${w("closeReason")}, ${reason});
    end if;
    return new;
  end if;
  if new.${w("state")} is distinct from old.${w("state")} then
    if ${closed} and ${state(`old.${w("state")}`, ["completed", "canceled"], true)} then
      new.${w("closedAt")} := now();
      new.${w("closeReason")} := coalesce(new.${w("closeReason")}, ${reason});
${
  ctx.has("items", "progress")
    ? `      if ${state(`new.${w("state")}`, ["completed"])} and new.${w("progress")} is not null then
        new.${w("progress")} := 100;
      end if;
`
    : ""
}      ${ctx.record({ type: "work_item.closed", payload: payload(`, 'state', new.${w("state")}, 'closeReason', new.${w("closeReason")}`), subject, tenant, audit: false })}
    elsif not (${closed}) and ${state(`old.${w("state")}`, ["completed", "canceled"])} then
      new.${w("closedAt")} := null;
      new.${w("closeReason")} := null;
      ${ctx.record({ type: "work_item.reopened", payload: payload(""), subject, tenant, audit: false })}
    end if;
  end if;
  new.${w("updatedAt")} := now();
  return new;
end;
$$;
${triggerGrant(`better_supabase.${guardName}()`)}
drop trigger if exists ${guardName} on ${t("items")};
create trigger ${guardName} before insert or update on ${t("items")}
for each row execute function better_supabase.${guardName}();
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("tasks");
  const maxAssignees = ctx.number("maxAssignees", 0);

  if (!Number.isInteger(maxAssignees) || maxAssignees < 0) {
    throw new TypeError(
      "blocks.tasks.options.maxAssignees must be 0 (no limit) or a positive integer",
    );
  }

  const n: WorkItemNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    create: sqlString(
      ctx.config.permissions["create"] ??
        ctx.permissionKey("write", keys.write),
    ),
    remove: sqlString(
      ctx.config.permissions["delete"] ??
        ctx.permissionKey("manage", keys.manage),
    ),
    authorCanDelete: ctx.flag("authorCanDelete", true),
    notify: ctx.flag("notify", true),
    actionPath: ctx.text("actionPath", ""),
    prefix: ctx.text("prefix", "TASK-"),
    maxAssignees,
    service: "(auth.role() = 'service_role')",
    extras: ctx.extraColumns("items", ["fields"]),
    e: (name) => ctx.resolved.entityNaming.rename(name),
  };

  return `${schemaPreamble(ctx)}
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.
${tables(ctx, n)}${guard(ctx, n)}${workItemFunctions(ctx, n)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_work_item",
      args: ["{id}", "jsonb", "uuid[]"],
      returns: "jsonb",
    },
    { name: "update_work_items", args: ["jsonb"], returns: "jsonb" },
    {
      name: "set_work_item_assignees",
      args: ["uuid", "uuid[]"],
      returns: "integer",
    },
    {
      name: "archive_work_item",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "delete_work_item", args: ["uuid"], returns: "boolean" },
    { name: "work_item_tree", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_work_items",
      args: ["{id}", "jsonb", "text", "uuid", "integer"],
      returns: "jsonb",
    },
    ...(ctx.hasTable("projects")
      ? [
          {
            name: "save_project",
            args: ["{id}", "uuid", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(ctx.hasTable("iterations")
      ? [
          {
            name: "save_iteration",
            args: ["{id}", "uuid", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    ...workItemExtrasContract(ctx),
  ];
}

/** How work items run on pipelines, with the items table's column names. */
const WORK_ITEM_STATES = [
  "triage",
  "backlog",
  "unstarted",
  "started",
  "completed",
  "canceled",
] as const;

const workItemPipeline = (
  own: BlockSqlContext,
): Readonly<Record<string, unknown>> => ({
  stage: own.colName("items", "stage"),
  pipeline: own.colName("items", "pipeline"),
  enteredAt: own.colName("items", "stageEnteredAt"),
  scope: own.colName("items", "team"),
  categories: {
    triage: "open",
    backlog: "open",
    unstarted: "open",
    started: "open",
    completed: "success",
    canceled: "failure",
  },
  status: {
    column: own.colName("items", "state"),
    values: Object.fromEntries(
      WORK_ITEM_STATES.flatMap((label) => {
        const [value] = own.appValues("items", "state", label);

        return value === undefined ? [] : [[label, value]];
      }),
    ),
  },
  stages: [
    { key: "triage", name: "Triage", category: "triage" },
    { key: "backlog", name: "Backlog", category: "backlog" },
    { key: "todo", name: "Todo", category: "unstarted" },
    { key: "in_progress", name: "In progress", category: "started" },
    { key: "in_review", name: "In review", category: "started" },
    { key: "done", name: "Done", category: "completed" },
    { key: "canceled", name: "Canceled", category: "canceled" },
  ],
});

const CONTRIBUTES: BlockContributes = {
  pipelines: (own) => {
    const { schema, name } = own.tableName("items");

    return [
      {
        type: own.resolved.entityNaming.rename("work_item"),
        table: `${schema}.${name}`,
        tenant: own.colName("items", "tenant"),
        entry: workItemPipeline(own),
      },
    ];
  },
  subjects: (own) => {
    const w = (column: string): string => `i.${own.col("items", column)}`;

    return [
      {
        work: `select 'assigned'::text, ${sqlString(workItemType(own))}::text, ${w("id")}::text, ${w("id")}::text, ${w("title")}::text,
      coalesce(${w("dueAt")}, ${own.has("assignees", "createdAt") ? `a.${own.col("assignees", "createdAt")}` : w("createdAt")})
    from ${own.table("assignees")} a
    join ${own.table("items")} i on ${w("id")} = a.${own.col("assignees", "item")}
    where a.${own.col("assignees", "user")} = v_me
      and ${own.is("items", "state", w("state"), ["completed", "canceled"], true)}
      and ${w("archivedAt")} is null
      and ${myWorkTenant(w("tenant"))}`,
      },
    ];
  },
};

export const WORK_ITEMS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "tasks",
  scopes: ["tenant"],
  title: "Work items",
  description:
    "Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.",
  requires: ["memberships", "permissions", "subjects", "pipelines"],
  // The pipelines module binds the work_items table, so the table comes first.
  before: "pipelines",
  integrates: [
    "outbox",
    "notifications",
    "numbering",
    "attachments",
    "reminders",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Work items gain checklists, recurrence (recurs_from), watchers and attachments on create and update.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
};
