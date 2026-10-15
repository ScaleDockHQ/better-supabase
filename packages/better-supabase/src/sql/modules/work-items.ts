import type { WorkItemsEvents } from "../../blocks/work-items/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  tenantIn,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import {
  workItemFunctions,
  type WorkItemNames,
} from "./work-items-functions.ts";

const ITEM = [
  "organizationId",
  "workItemId",
  "subjectType",
  "subjectId",
  "title",
] as const;

const EVENTS: ModuleEvents<WorkItemsEvents> = {
  "work_item.created": { subject: "work-items", payload: [...ITEM] },
  "work_item.updated": { subject: "work-items", payload: [...ITEM, "fields"] },
  "work_item.assigned": {
    subject: "work-items",
    payload: [...ITEM, "assigneeIds"],
  },
  "work_item.closed": {
    subject: "work-items",
    payload: [...ITEM, "state", "closeReason"],
  },
  "work_item.reopened": { subject: "work-items", payload: [...ITEM] },
  "work_item.archived": { subject: "work-items", payload: [...ITEM] },
  "work_item.deleted": { subject: "work-items", payload: [...ITEM] },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_work_item_create",
    "after_work_item_create",
    "before_work_item_update",
    "after_work_item_update",
  ],
  options: ["prefix", "maxAssignees", "extraColumns"],
  tables: {
    items: {
      name: "work_items",
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
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    assignees: {
      name: "work_item_assignees",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        tenant: "tenant_id",
        item: "work_item_id",
        user: "user_id",
        createdAt: "created_at",
      },
    },
    projects: {
      name: "projects",
      optionalTable: true,
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
    },
    iterations: {
      name: "iterations",
      optionalTable: true,
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
    },
  },
};

function tables(ctx: ModuleContext, n: WorkItemNames): string {
  if (!ctx.manages) return "";
  const { t, c } = n;
  const w = (column: string): string => c("items", column);
  const a = (column: string): string => c("assignees", column);
  const read = (
    table: string,
  ): string => `drop policy if exists ${ctx.tableName(table).name}_read on ${t(table)};
create policy ${ctx.tableName(table).name}_read on ${t(table)} for select to authenticated
using (${tenantIn(c(table, "tenant"), n.read)});`;
  const p = (column: string): string => c("projects", column);
  const i = (column: string): string => c("iterations", column);
  const projects = ctx.hasTable("projects")
    ? `
create table if not exists ${t("projects")} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("key")} text not null check (${p("key")} ~ '^[A-Z][A-Z0-9]{0,9}$'),
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("owner")} uuid,
  ${p("status")} text not null default 'planned' check (${p("status")} in ('planned', 'active', 'paused', 'completed', 'canceled')),
  ${p("startOn")} date,
  ${p("targetOn")} date,
  ${p("archivedAt")} timestamptz,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  unique (${p("tenant")}, ${p("key")}),
  check (${p("targetOn")} is null or ${p("startOn")} is null or ${p("targetOn")} >= ${p("startOn")})
);
${lockTable(t("projects"), { read: true })}
${read("projects")}
`
    : "";
  const iterations = ctx.hasTable("iterations")
    ? `
create table if not exists ${t("iterations")} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("team")} uuid,
  ${i("name")} text not null check (length(${i("name")}) between 1 and 200),
  ${i("startsOn")} date not null,
  ${i("endsOn")} date not null,
  ${i("createdAt")} timestamptz not null default now(),
  check (${i("endsOn")} >= ${i("startsOn")})
);
create index if not exists iterations_tenant_idx on ${t("iterations")} (${i("tenant")}, ${i("team")}, ${i("startsOn")});
${lockTable(t("iterations"), { read: true })}
${read("iterations")}
`
    : "";
  return `${projects}${iterations}
create table if not exists ${t("items")} (
  ${w("id")} uuid primary key default gen_random_uuid(),
  ${w("tenant")} ${ctx.idType} not null,
  ${w("number")} bigint not null,
  ${w("identifier")} text not null,
  ${w("title")} text not null check (length(${w("title")}) between 1 and 500),
  ${w("body")} text,
  ${w("parent")} uuid references ${t("items")} (${w("id")}) on delete cascade,
  ${w("team")} uuid,
  ${w("project")} uuid${ctx.hasTable("projects") ? ` references ${t("projects")} (${p("id")}) on delete set null` : ""},
  ${w("iteration")} uuid${ctx.hasTable("iterations") ? ` references ${t("iterations")} (${i("id")}) on delete set null` : ""},
  ${w("priority")} smallint not null default 0 check (${w("priority")} between 0 and 4),
  ${w("estimate")} numeric(10, 2) check (${w("estimate")} >= 0),
  ${w("progress")} smallint check (${w("progress")} between 0 and 100),
  ${w("startAt")} timestamptz,
  ${w("endAt")} timestamptz,
  ${w("dueAt")} timestamptz,
  ${w("pipeline")} uuid,
  ${w("stage")} uuid,
  ${w("stageEnteredAt")} timestamptz,
  ${w("state")} text not null default 'backlog' check (${w("state")} in ('triage', 'backlog', 'unstarted', 'started', 'completed', 'canceled')),
  ${w("closeReason")} text check (${w("closeReason")} in ('completed', 'not_planned', 'duplicate')),
  ${w("closedAt")} timestamptz,
  ${w("locked")} boolean not null default false,
  ${w("rank")} text collate "C" not null default 'V',
  ${w("archivedAt")} timestamptz,
  ${w("createdBy")} uuid,
  ${w("createdAt")} timestamptz not null default now(),
  ${w("updatedAt")} timestamptz not null default now(),
  unique (${w("tenant")}, ${w("number")}),
  check (${w("endAt")} is null or ${w("startAt")} is null or ${w("endAt")} >= ${w("startAt")})
);
create index if not exists work_items_board_idx on ${t("items")} (${w("pipeline")}, ${w("stage")}, ${w("rank")});
create index if not exists work_items_parent_idx on ${t("items")} (${w("parent")});
create index if not exists work_items_project_idx on ${t("items")} (${w("project")});
create index if not exists work_items_iteration_idx on ${t("items")} (${w("iteration")});
create index if not exists work_items_due_idx on ${t("items")} (${w("tenant")}, ${w("dueAt")}) where ${w("closedAt")} is null;${addExtraColumns(t("items"), ctx.extraColumns("items"))}
${lockTable(t("items"), { read: true })}
${read("items")}

create table if not exists ${t("assignees")} (
  ${a("tenant")} ${ctx.idType} not null,
  ${a("item")} uuid not null references ${t("items")} (${w("id")}) on delete cascade,
  ${a("user")} uuid not null,
  ${a("createdAt")} timestamptz not null default now(),
  primary key (${a("item")}, ${a("user")})
);
create index if not exists work_item_assignees_user_idx on ${t("assignees")} (${a("user")});
${lockTable(t("assignees"), { read: true })}
${read("assignees")}
`;
}

/**
 * The guard trigger: no parent cycles, a locked item keeps its dates, a
 * closing state stamps closed_at and a close reason and records
 * work_item.closed, and reopening clears both.
 */
function guard(ctx: ModuleContext, n: WorkItemNames): string {
  const { t, c } = n;
  const w = (column: string): string => c("items", column);
  const payload = (extra: string): string =>
    `jsonb_build_object('organizationId', new.${w("tenant")}, 'workItemId', new.${w("id")}, 'subjectType', 'work_item', 'subjectId', new.${w("id")}::text, 'title', new.${w("title")}${extra})`;
  const subject = `'work-items/' || new.${w("id")}::text`;
  const tenant = `new.${w("tenant")}::text`;
  const closed = `new.${w("state")} in ('completed', 'canceled')`;
  const dates = [w("startAt"), w("endAt"), w("dueAt")]
    .map((column) => `new.${column} is distinct from old.${column}`)
    .join(" or ");
  return `
create or replace function better_supabase.bs_work_item_guard()
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
      new.${w("closeReason")} := coalesce(new.${w("closeReason")}, case new.${w("state")} when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new.${w("state")} is distinct from old.${w("state")} then
    if ${closed} and old.${w("state")} not in ('completed', 'canceled') then
      new.${w("closedAt")} := now();
      new.${w("closeReason")} := coalesce(new.${w("closeReason")}, case new.${w("state")} when 'completed' then 'completed' else 'not_planned' end);
      if new.${w("state")} = 'completed' and new.${w("progress")} is not null then
        new.${w("progress")} := 100;
      end if;
      ${ctx.record({ type: "work_item.closed", payload: payload(`, 'state', new.${w("state")}, 'closeReason', new.${w("closeReason")}`), subject, tenant, audit: false })}
    elsif not (${closed}) and old.${w("state")} in ('completed', 'canceled') then
      new.${w("closedAt")} := null;
      new.${w("closeReason")} := null;
      ${ctx.record({ type: "work_item.reopened", payload: payload(""), subject, tenant, audit: false })}
    end if;
  end if;
  new.${w("updatedAt")} := now();
  return new;
end;
$$;
drop trigger if exists bs_work_item_guard on ${t("items")};
create trigger bs_work_item_guard before insert or update on ${t("items")}
for each row execute function better_supabase.bs_work_item_guard();
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const keys = moduleOperations("work-items");
  const maxAssignees = ctx.number("maxAssignees", 0);
  if (!Number.isInteger(maxAssignees) || maxAssignees < 0) {
    throw new TypeError(
      "blocks.work-items.options.maxAssignees must be 0 (no limit) or a positive integer",
    );
  }
  const n: WorkItemNames = {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    c: (table, column) => ctx.col(table, column),
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    manage: ctx.permission("manage", keys.manage),
    prefix: ctx.text("prefix", "TASK-"),
    maxAssignees,
    service: "(auth.role() = 'service_role')",
  };
  return `${schemaPreamble(ctx)}
-- Work items on pipelines: issues and tasks with an identifier, a parent,
-- assignees, a priority, dates, projects and iterations.
${tables(ctx, n)}${guard(ctx, n)}${workItemFunctions(ctx, n)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
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
  ];
}

export const WORK_ITEMS: ModuleDefinition = {
  name: "work-items",
  title: "Work items",
  description:
    "Issues and tasks on pipelines: identifiers, parents without cycles, several assignees, priority 0 to 4, estimates, start, end and due dates, locking, projects, iterations, batched edits and a progress tree.",
  requires: ["tenant", "access", "subjects", "pipelines"],
  // The pipelines module binds the work_items table, so the table comes first.
  before: "pipelines",
  integrates: ["outbox", "notifications", "number-sequences"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
