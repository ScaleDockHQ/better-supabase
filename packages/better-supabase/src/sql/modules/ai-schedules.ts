import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Columns } from "./module-columns.ts";

import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  withExtraFields,
  writeExtraColumns,
  raise,
  replaceColumnCheck,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  revokeTable,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const RUN_STATES = "'queued', 'running', 'completed', 'failed'";

const TASKS = {
  id: "id",
  tenant: "tenant_id",
  user: "user_id",
  chat: "chat_id",
  agent: "agent_id",
  title: "title",
  prompt: "prompt",
  cron: "cron",
  timezone: "timezone",
  enabled: "enabled",
  nextRunAt: "next_run_at",
  lastRunAt: "last_run_at",
  source: "source",
  externalId: "external_id",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const RUNS = {
  id: "id",
  task: "task_id",
  tenant: "tenant_id",
  user: "user_id",
  status: "status",
  scheduledFor: "scheduled_at",
  chat: "chat_id",
  error: "error",
  startedAt: "started_at",
  finishedAt: "finished_at",
  createdAt: "created_at",
} as const;

const NAMES: BlockSqlNames = {
  entities: {
    ai_scheduled_task: {
      table: "tasks",
      singular: "ai_scheduled_task",
      primary: true,
    },
  },
  options: ["queue", "staleAfter", "maxPrompt"],
  tables: {
    tasks: {
      name: "ai_scheduled_tasks",
      columns: TASKS,
      lifecycle: { user: "user", tenant: "tenant" },
      app: {},
      optional: [
        "chat",
        "agent",
        "lastRunAt",
        "updatedAt",
        "source",
        "externalId",
      ],
    },
    runs: {
      name: "ai_task_runs",
      columns: RUNS,
      lifecycle: { user: "user", tenant: "tenant" },
      app: {},
      optional: ["chat", "error", "finishedAt"],
      typed: ["status"],
    },
  },
};

/** The source of tasks this module claims and runs itself. */
const SELF_SOURCE = "ai-schedules";

const QUEUE = /^[a-z_][a-z0-9_]{0,46}$/;
const INTERVAL = /^\d+ (second|minute|hour|day)s?$/;

/**
 * The quoted columns of `table`. A column the app's table lacks is empty, so
 * every use of an optional column checks `ctx.has` first.
 */
function presentColumns<T extends Readonly<Record<string, string>>>(
  ctx: BlockSqlContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [
      key,
      ctx.has(table, key) ? ctx.col(table, key) : "",
    ]),
  ) as Columns<T>;
}

/** `jsonb_build_object` over a spec's columns, null for the ones missing. */
function presentJson(
  ctx: BlockSqlContext,
  table: string,
  spec: Readonly<Record<string, string>>,
  row: string,
): string {
  const pairs = Object.entries(spec).map(
    ([key, name]) =>
      `'${name}', ${ctx.has(table, key) ? `${row}.${ctx.col(table, key)}` : "null"}`,
  );

  return `jsonb_build_object(${pairs.join(", ")})`;
}

function build(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = presentColumns(ctx, "tasks", TASKS);
  const r = presentColumns(ctx, "runs", RUNS);

  const task = (column: keyof typeof TASKS): boolean =>
    ctx.has("tasks", column);

  const run = (column: keyof typeof RUNS): boolean => ctx.has("runs", column);
  const status = (value: string): string => ctx.cast("runs", "status", value);
  const tasks = ctx.table("tasks");
  const runs = ctx.table("runs");
  const permissions = moduleOperations("ai-schedules");
  const create = ctx.permission("create", permissions.create);
  const manage = ctx.permission("manage", permissions.manage);
  const maxPrompt = ctx.number("maxPrompt", 20_000);
  const queue = ctx.text("queue", "ai_task_run");

  if (!QUEUE.test(queue)) {
    throw new TypeError(
      "blocks.ai-schedules.options.queue must be a lowercase queue name of at most 47 characters",
    );
  }

  const staleAfter = ctx.text("staleAfter", "30 minutes");

  if (!INTERVAL.test(staleAfter)) {
    throw new TypeError(
      'blocks["ai-schedules"].options.staleAfter must be an interval such as "30 minutes"',
    );
  }

  // A mirrored task is owned by another scheduler (source is not
  // 'ai-schedules'): this module stores it and its runs but never claims it.
  const mirror = task("source") && task("externalId");

  const owned = mirror ? `x.${t.source} = '${SELF_SOURCE}'` : "true";

  const agents = ctx.installed("agents") ? ctx.of("agents") : undefined;

  const agentReference = agents
    ? ` references ${agents.table("agents")} (${agents.col("agents", "id")}) on delete set null`
    : "";

  const chat = ctx.installed("ai-chat") ? ctx.of("ai-chat") : undefined;

  const chatOwned = chat
    ? `exists (select 1 from ${chat.table("chats")} c where c.${chat.col("chats", "id")} = v_chat and c.${chat.col("chats", "owner")} = v_row.${t.user} and c.${chat.col("chats", "tenant")} = v_row.${t.tenant})`
    : "false";

  const agentUsable = agents
    ? `exists (select 1 from ${agents.table("agents")} g where g.${agents.col("agents", "id")} = v_agent and g.${agents.col("agents", "tenant")} = v_row.${t.tenant} and (g.${agents.col("agents", "owner")} = v_row.${t.user} or g.${agents.col("agents", "publishedAt")} is not null))`
    : "false";

  const extras = ctx.extraColumns("tasks", [
    ...Object.values(TASKS),
    "last_run",
    "fields",
  ]);

  const taskJson = (row: string): string =>
    withExtraFields(presentJson(ctx, "tasks", TASKS, row), row, extras);

  const runJson = (row: string): string => presentJson(ctx, "runs", RUNS, row);

  const taskIdKey = { expr: `x.${t.id}`, dir: "asc", type: "uuid" } as const;

  const taskCreated = [
    { expr: `x.${t.createdAt}`, dir: "desc", type: "timestamptz" },
    taskIdKey,
  ] as const;

  const taskPage = {
    name: "page_ai_tasks",
    from: tasks,
    alias: "x",
    where: [
      `x.${t.tenant} = page_ai_tasks.tenant`,
      `(${filterFlag("all")} or x.${t.user} = auth.uid())`,
      filterAny("enabled", `x.${t.enabled}::text`),
      `(v_search is null or x.${t.title} ilike v_search or x.${t.prompt} ilike v_search)`,
    ],
    keys: taskCreated,
    sorts: {
      createdAt: taskCreated,
      title: [
        { expr: `lower(x.${t.title})`, dir: "asc", type: "text" },
        taskIdKey,
      ],
      nextRunAt: [
        {
          expr: `coalesce(x.${t.nextRunAt}, 'infinity'::timestamptz)`,
          dir: "asc",
          type: "timestamptz",
        },
        taskIdKey,
      ],
    },
    facets: { enabled: `x.${t.enabled}` },
    rowJson: `${taskJson("x")} || jsonb_build_object('last_run', (
      select ${runJson("y")} from ${runs} y where y.${r.task} = x.${t.id} order by y.${r.createdAt} desc limit 1
    ))`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("AI_TASK_INVALID", message, "22023"),
  } as const;

  const line = (present: boolean, definition: string): string =>
    present ? `\n  ${definition},` : "";

  const enqueue = (run: string): string =>
    ctx.installed("queue")
      ? `
    ${ctx.enqueue(queue, `jsonb_build_object('run_id', ${run})`, `'ai-task:' || ${run}::text`)}`
      : "";

  const mayEdit = (row: string): string =>
    `(${SERVICE_CALLER} or coalesce(${row}.${t.user} = auth.uid(), false) or ${ctx.scope.can(`${row}.${t.tenant}`, manage)})`;

  const notFound = raise(
    "task % not found",
    "P0002",
    "AI_TASK_NOT_FOUND",
    "v_id",
  );

  const finished = run("finishedAt")
    ? `, ${r.finishedAt} = case when record_ai_task_run.status in ('completed', 'failed') then now() else y.${r.finishedAt} end`
    : "";

  const mirrorSql = mirror
    ? `

-- Stores a task another scheduler runs (service role), such as an eve
-- schedule: the row is keyed by (tenant, source, external_id), claim_due_ai_tasks
-- never claims it, and the other scheduler reports its occurrences with
-- record_ai_task_run. source may not be '${SELF_SOURCE}'.
create or replace function ${fn("mirror_ai_task")}(tenant ${id}, user_id uuid, source text, external_id text, fields jsonb default '{}', next_run_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${tasks}%rowtype;
begin
  if mirror_ai_task.source is null or mirror_ai_task.source = '${SELF_SOURCE}' or length(mirror_ai_task.source) not between 1 and 64 then
    ${raise("source must name another scheduler", "22023", "AI_TASK_INVALID")}
  end if;
  if mirror_ai_task.external_id is null or length(mirror_ai_task.external_id) not between 1 and 200 then
    ${raise("external_id is required", "22023", "AI_TASK_INVALID")}
  end if;
  if jsonb_typeof(mirror_ai_task.fields) is distinct from 'object' then
    ${raise("fields must be an object", "22023", "AI_TASK_INVALID")}
  end if;
  select * into v_row from ${tasks} x
  where x.${t.tenant} = mirror_ai_task.tenant and x.${t.source} = mirror_ai_task.source and x.${t.externalId} = mirror_ai_task.external_id
  for update;
  if not found then
    insert into ${tasks} (${t.tenant}, ${t.user}, ${t.title}, ${t.prompt}, ${t.cron}, ${t.source}, ${t.externalId})
    values (mirror_ai_task.tenant, mirror_ai_task.user_id, mirror_ai_task.fields ->> 'title', mirror_ai_task.fields ->> 'prompt', mirror_ai_task.fields ->> 'cron', mirror_ai_task.source, mirror_ai_task.external_id)
    returning * into v_row;
  end if;
  update ${tasks} x set
    ${t.title} = coalesce(mirror_ai_task.fields ->> 'title', x.${t.title}),
    ${t.prompt} = coalesce(mirror_ai_task.fields ->> 'prompt', x.${t.prompt}),
    ${t.cron} = coalesce(mirror_ai_task.fields ->> 'cron', x.${t.cron}),
    ${t.timezone} = coalesce(mirror_ai_task.fields ->> 'timezone', x.${t.timezone}),
    ${t.enabled} = coalesce((mirror_ai_task.fields ->> 'enabled')::boolean, x.${t.enabled}),
    ${t.nextRunAt} = case when coalesce((mirror_ai_task.fields ->> 'enabled')::boolean, x.${t.enabled}) then mirror_ai_task.next_run_at else null end${task("updatedAt") ? `,\n    ${t.updatedAt} = now()` : ""}
  where x.${t.id} = v_row.${t.id}
  returning * into v_row;
  return ${taskJson("v_row")};
end;
$$;
${serviceGrant(`${fn("mirror_ai_task")}(${id}, uuid, text, text, jsonb, timestamptz)`)}

-- Removes a mirrored task and its runs (service role).
create or replace function ${fn("delete_mirrored_ai_task")}(tenant ${id}, source text, external_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${tasks} x
  where x.${t.tenant} = delete_mirrored_ai_task.tenant and x.${t.source} = delete_mirrored_ai_task.source
    and x.${t.externalId} = delete_mirrored_ai_task.external_id and x.${t.source} <> '${SELF_SOURCE}';
  return found;
end;
$$;
${serviceGrant(`${fn("delete_mirrored_ai_task")}(${id}, text, text)`)}

-- Records one occurrence of a mirrored task (service role): one run per
-- scheduled_for, created on first sight and updated after. status is queued,
-- running, completed or failed. Returns null when the task is unknown.
create or replace function ${fn("record_ai_task_run")}(tenant ${id}, source text, external_id text, scheduled_for timestamptz, status text, error text default null, chat_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task ${tasks}%rowtype;
  v_run ${runs}%rowtype;
begin
  if record_ai_task_run.status not in (${RUN_STATES}) then
    ${raise("% is not a run status", "22023", "AI_TASK_INVALID", "record_ai_task_run.status")}
  end if;
  select * into v_task from ${tasks} x
  where x.${t.tenant} = record_ai_task_run.tenant and x.${t.source} = record_ai_task_run.source
    and x.${t.externalId} = record_ai_task_run.external_id and x.${t.source} <> '${SELF_SOURCE}'
  for update;
  if not found then
    return null;
  end if;
  select * into v_run from ${runs} y where y.${r.task} = v_task.${t.id} and y.${r.scheduledFor} = record_ai_task_run.scheduled_for for update;
  if not found then
    insert into ${runs} (${r.task}, ${r.tenant}, ${r.user}, ${r.scheduledFor}, ${r.status})
    values (v_task.${t.id}, v_task.${t.tenant}, v_task.${t.user}, record_ai_task_run.scheduled_for, ${status("record_ai_task_run.status")})
    returning * into v_run;
  end if;
  update ${runs} y set ${[
    `${r.status} = ${status("record_ai_task_run.status")}`,
    `${r.startedAt} = case when record_ai_task_run.status = 'queued' then y.${r.startedAt} else coalesce(y.${r.startedAt}, now()) end`,
    ...(run("error")
      ? [`${r.error} = left(record_ai_task_run.error, 4000)`]
      : []),
    ...(run("chat")
      ? [`${r.chat} = coalesce(record_ai_task_run.chat_id, y.${r.chat})`]
      : []),
  ].join(", ")}${finished}
  where y.${r.id} = v_run.${r.id}
  returning * into v_run;${
    task("lastRunAt")
      ? `
  update ${tasks} x set ${t.lastRunAt} = greatest(coalesce(x.${t.lastRunAt}, record_ai_task_run.scheduled_for), record_ai_task_run.scheduled_for) where x.${t.id} = v_task.${t.id};`
      : ""
  }
  return ${runJson("v_run")};
end;
$$;
${serviceGrant(`${fn("record_ai_task_run")}(${id}, text, text, timestamptz, text, text, uuid)`)}`
    : "";

  return `${schemaPreamble(ctx)}
-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table if not exists ${tasks} (
  ${t.id} uuid primary key default gen_random_uuid(),
  ${t.tenant} ${id} not null,
  ${t.user} uuid not null references auth.users (id) on delete cascade,${line(task("chat"), `${t.chat} uuid`)}${line(task("agent"), `${t.agent} uuid${agentReference}`)}
  ${t.title} text not null check (length(${t.title}) between 1 and 200),
  ${t.prompt} text not null check (length(${t.prompt}) between 1 and ${maxPrompt}),
  ${t.cron} text not null check (length(${t.cron}) between 1 and 200),
  ${t.timezone} text not null default 'UTC' check (length(${t.timezone}) between 1 and 64),
  ${t.enabled} boolean not null default true,
  ${t.nextRunAt} timestamptz,${line(task("lastRunAt"), `${t.lastRunAt} timestamptz`)}${line(task("source"), `${t.source} text not null default '${SELF_SOURCE}' check (length(${t.source}) between 1 and 64)`)}${line(task("externalId"), `${t.externalId} text check (length(${t.externalId}) between 1 and 200)`)}
  ${t.createdAt} timestamptz not null default now()${task("updatedAt") ? `,\n  ${t.updatedAt} timestamptz not null default now()` : ""}
);
create index if not exists ${ctx.naming.rename("ai_scheduled_tasks_due_idx")} on ${tasks} (${t.nextRunAt}) where ${t.enabled};
create index if not exists ${ctx.naming.rename("ai_scheduled_tasks_user_idx")} on ${tasks} (${t.user}, ${t.tenant});${task("agent") ? `\ncreate index if not exists ${ctx.naming.rename("ai_scheduled_tasks_agent_idx")} on ${tasks} (${t.agent});` : ""}
${
  mirror
    ? `create unique index if not exists ${ctx.naming.rename("ai_scheduled_tasks_external_idx")} on ${tasks} (${t.tenant}, ${t.source}, ${t.externalId}) where ${t.externalId} is not null;
`
    : ""
}alter table ${tasks} enable row level security;
${revokeTable(tasks)}
grant select on ${tasks} to authenticated;
grant all on ${tasks} to service_role;
${renderPolicy(makePolicy({ table: tasks, name: ctx.naming.rename("ai_scheduled_tasks_read"), command: "select", roles: ["authenticated"], using: `${t.user} = (select auth.uid()) or ${ctx.scope.check(t.tenant, manage)}` }), { target: tasks })}

create table if not exists ${runs} (
  ${r.id} uuid primary key default gen_random_uuid(),
  ${r.task} uuid not null references ${tasks} (${t.id}) on delete cascade,
  ${r.tenant} ${id} not null,
  ${r.user} uuid not null references auth.users (id) on delete cascade,
  ${r.status} text not null default 'queued' check (${r.status} in (${RUN_STATES})),
  ${r.scheduledFor} timestamptz not null,${line(run("chat"), `${r.chat} uuid`)}${line(run("error"), `${r.error} text check (length(${r.error}) <= 4000)`)}
  ${r.startedAt} timestamptz,${line(run("finishedAt"), `${r.finishedAt} timestamptz`)}
  ${r.createdAt} timestamptz not null default now()
);
create index if not exists ai_task_runs_task_idx on ${runs} (${r.task}, ${r.createdAt} desc);
create index if not exists ai_task_runs_user_idx on ${runs} (${r.user});
create index if not exists ai_task_runs_open_idx on ${runs} (${r.status}, ${r.startedAt}) where ${r.status} in ('queued', 'running');
alter table ${runs} enable row level security;
${revokeTable(runs)}
grant select on ${runs} to authenticated;
grant all on ${runs} to service_role;
${renderPolicy(makePolicy({ table: runs, name: "ai_task_runs_read", command: "select", roles: ["authenticated"], using: `${r.user} = (select auth.uid()) or ${ctx.scope.check(r.tenant, manage)}` }), { target: runs })}

-- Creates (id null) or changes a task. Only the service role sets
-- next_run_at; for anyone else a new task, or a changed cron or timezone,
-- clears it and the scheduler computes the next occurrence on its next
-- tick. Pausing clears it, so a resumed task waits for its next occurrence.
-- chat_id must be a chat of the task's user in the tenant, and agent_id an
-- agent of the tenant that user owns or that is published.
create or replace function ${fn("save_ai_task")}(tenant ${id}, id uuid default null, fields jsonb default '{}', next_run_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_ai_task.id;
  v_row ${tasks}%rowtype;
  v_service boolean := ${SERVICE_CALLER};
  v_chat uuid;
  v_agent uuid;
begin
  if jsonb_typeof(save_ai_task.fields) is distinct from 'object' then
    ${raise("fields must be an object", "22023", "AI_TASK_INVALID")}
  end if;
  if save_ai_task.fields ? 'timezone' then
    begin
      perform now() at time zone (save_ai_task.fields ->> 'timezone');
    exception when others then
      ${raise("% is not a time zone", "22023", "AI_TASK_INVALID", "save_ai_task.fields ->> 'timezone'")}
    end;
  end if;
  if v_id is null then
    if not (${SERVICE_CALLER} or ${ctx.scope.can("save_ai_task.tenant", create)}) or auth.uid() is null then
      ${raise("you may not schedule tasks here", "42501", "AI_TASK_FORBIDDEN")}
    end if;
    insert into ${tasks} (${t.tenant}, ${t.user}, ${t.title}, ${t.prompt}, ${t.cron})
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from ${tasks} x where x.${t.id} = v_id and x.${t.tenant} = save_ai_task.tenant for update;
    if not found or not ${mayEdit("v_row")} then
      ${notFound}
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not ${chatOwned}
  then
    ${raise("chat % is not a chat of this task's user", "42501", "AI_TASK_CHAT_FORBIDDEN", "v_chat")}
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not ${agentUsable}
  then
    ${raise("agent % is not an agent this task's user may use", "42501", "AI_TASK_AGENT_FORBIDDEN", "v_agent")}
  end if;
  update ${tasks} x set
    ${t.title} = coalesce(save_ai_task.fields ->> 'title', x.${t.title}),
    ${t.prompt} = coalesce(save_ai_task.fields ->> 'prompt', x.${t.prompt}),
    ${t.cron} = coalesce(save_ai_task.fields ->> 'cron', x.${t.cron}),
    ${t.timezone} = coalesce(save_ai_task.fields ->> 'timezone', x.${t.timezone}),${task("chat") ? `\n    ${t.chat} = case when save_ai_task.fields ? 'chat_id' then (save_ai_task.fields ->> 'chat_id')::uuid else x.${t.chat} end,` : ""}${task("agent") ? `\n    ${t.agent} = case when save_ai_task.fields ? 'agent_id' then (save_ai_task.fields ->> 'agent_id')::uuid else x.${t.agent} end,` : ""}
    ${t.enabled} = coalesce((save_ai_task.fields ->> 'enabled')::boolean, x.${t.enabled}),
    ${t.nextRunAt} = case
      when (save_ai_task.fields ->> 'enabled')::boolean is false then null
      when v_service and (save_ai_task.next_run_at is not null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone') then save_ai_task.next_run_at
      when save_ai_task.id is null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone' then null
      else x.${t.nextRunAt} end${task("updatedAt") ? `,\n    ${t.updatedAt} = now()` : ""}
  where x.${t.id} = v_row.${t.id}
  returning * into v_row;${writeExtraColumns(tasks, extras, "save_ai_task.fields", `x.${t.id} = v_row.${t.id}`, "v_row")}
  return ${taskJson("v_row")};
end;
$$;
${userGrant(`${fn("save_ai_task")}(${id}, uuid, jsonb, timestamptz)`)}

create or replace function ${fn("delete_ai_task")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_ai_task.id;
  v_row ${tasks}%rowtype;
begin
  select * into v_row from ${tasks} x where x.${t.id} = v_id for update;
  if not found or not ${mayEdit("v_row")} then
    return false;
  end if;
  delete from ${tasks} x where x.${t.id} = v_id;
  return true;
end;
$$;
${userGrant(`${fn("delete_ai_task")}(uuid)`)}

-- The caller's tasks in a tenant (or every task, for ${manage}).
create or replace function ${fn("list_ai_tasks")}(tenant ${id}, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${taskJson("x")} || jsonb_build_object('last_run', (
    select ${runJson("y")} from ${runs} y where y.${r.task} = x.${t.id} order by y.${r.createdAt} desc limit 1
  )) order by x.${t.createdAt} desc), '[]')
  from ${tasks} x
  where x.${t.tenant} = list_ai_tasks.tenant and (not list_ai_tasks.mine or x.${t.user} = auth.uid())
$$;
${userGrant(`${fn("list_ai_tasks")}(${id}, boolean)`)}

-- The caller's tasks in a tenant as a keyset page (ADR 1077), newest first.
-- filters is { all (true reads every task of the tenant that the caller can
-- read), enabled (a value or a list), search (title, prompt), sort (createdAt,
-- title, nextRunAt), direction, facet, count, limit, after, offset, paged,
-- total, totalCap }.
create or replace function ${fn("page_ai_tasks")}(tenant ${id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_ai_tasks.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(taskPage)}
begin
  ${listBody(taskPage)}
end;
$$;
${userGrant(`${fn("page_ai_tasks")}(${id}, jsonb)`)}

-- One task the caller can read, with its last run, or null.
create or replace function ${fn("get_ai_task")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${taskJson("x")} || jsonb_build_object('last_run', (
    select ${runJson("y")} from ${runs} y where y.${r.task} = x.${t.id} order by y.${r.createdAt} desc limit 1
  ))
  from ${tasks} x where x.${t.id} = get_ai_task.id
$$;
${userGrant(`${fn("get_ai_task")}(uuid)`)}

create or replace function ${fn("list_ai_task_runs")}(task_id uuid, max_rows integer default 20)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${runJson("y")} order by y.${r.createdAt} desc), '[]')
  from (
    select * from ${runs} y0 where y0.${r.task} = list_ai_task_runs.task_id
    order by y0.${r.createdAt} desc limit least(greatest(list_ai_task_runs.max_rows, 1), 200)
  ) y
$$;
${userGrant(`${fn("list_ai_task_runs")}(uuid, integer)`)}

-- Claims due tasks (service role): queues a run for each, clears its
-- next_run_at until the scheduler sets the next one, fails runs that ran, or
-- waited in the queue, longer than ${staleAfter}, and returns the runs and
-- the enabled tasks that need a next_run_at.
create or replace function ${fn("claim_due_ai_tasks")}(batch integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task ${tasks}%rowtype;
  v_run ${runs}%rowtype;
  v_runs jsonb := '[]';
  v_unscheduled jsonb;
begin
  update ${runs} y set ${[
    `${r.status} = ${status("'failed'")}`,
    ...(run("error") ? [`${r.error} = 'timed out'`] : []),
    ...(run("finishedAt") ? [`${r.finishedAt} = now()`] : []),
  ].join(", ")}
  where ((y.${r.status} = 'running' and y.${r.startedAt} < now() - interval '${staleAfter}')
     or (y.${r.status} = 'queued' and y.${r.createdAt} < now() - interval '${staleAfter}'))${
       mirror
         ? `
    and exists (select 1 from ${tasks} x where x.${t.id} = y.${r.task} and ${owned})`
         : ""
     };
  for v_task in
    select * from ${tasks} x
    where x.${t.enabled} and x.${t.nextRunAt} <= now() and ${owned}
    order by x.${t.nextRunAt}
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into ${runs} (${r.task}, ${r.tenant}, ${r.user}, ${r.scheduledFor}${run("chat") ? `, ${r.chat}` : ""})
    values (v_task.${t.id}, v_task.${t.tenant}, v_task.${t.user}, v_task.${t.nextRunAt}${run("chat") ? `, ${task("chat") ? `v_task.${t.chat}` : "null"}` : ""})
    returning * into v_run;
    update ${tasks} x set ${t.nextRunAt} = null${task("lastRunAt") ? `, ${t.lastRunAt} = now()` : ""} where x.${t.id} = v_task.${t.id};${enqueue(`v_run.${r.id}`)}
    v_runs := v_runs || jsonb_build_array(${runJson("v_run")});
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${t.id}, 'cron', x.${t.cron}, 'timezone', x.${t.timezone})), '[]')
  into v_unscheduled
  from ${tasks} x where x.${t.enabled} and x.${t.nextRunAt} is null and ${owned};
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$$;
${serviceGrant(`${fn("claim_due_ai_tasks")}(integer)`)}

-- Sets next_run_at for tasks: items is { "items": [{ "id", "next_run_at" }] } (service role).
create or replace function ${fn("schedule_ai_tasks")}(items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_items jsonb := case when jsonb_typeof(schedule_ai_tasks.items) = 'object' then schedule_ai_tasks.items -> 'items' else schedule_ai_tasks.items end;
  v_count integer;
begin
  update ${tasks} x set ${t.nextRunAt} = (item ->> 'next_run_at')::timestamptz
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  where x.${t.id} = (item ->> 'id')::uuid and x.${t.enabled} and x.${t.nextRunAt} is null and ${owned};
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("schedule_ai_tasks")}(jsonb)`)}

-- Moves a queued run to running and returns it with its task, or null when
-- another worker took it (service role).
create or replace function ${fn("start_ai_task_run")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ${runs}%rowtype;
  v_task ${tasks}%rowtype;
begin
  update ${runs} y set ${r.status} = ${status("'running'")}, ${r.startedAt} = now()
  where y.${r.id} = start_ai_task_run.id and y.${r.status} = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from ${tasks} x where x.${t.id} = v_run.${r.task};
  return ${runJson("v_run")} || jsonb_build_object('task', ${taskJson("v_task")});
end;
$$;
${serviceGrant(`${fn("start_ai_task_run")}(uuid)`)}

-- Finishes a running run (service role); chat_id records the chat it wrote to.
create or replace function ${fn("finish_ai_task_run")}(id uuid, succeeded boolean, error text default null, chat_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task uuid;
begin
  update ${runs} y set
    ${[
      `${r.status} = ${status("case when finish_ai_task_run.succeeded then 'completed' else 'failed' end")}`,
      ...(run("error")
        ? [`${r.error} = left(finish_ai_task_run.error, 4000)`]
        : []),
      ...(run("chat")
        ? [`${r.chat} = coalesce(finish_ai_task_run.chat_id, y.${r.chat})`]
        : []),
      ...(run("finishedAt") ? [`${r.finishedAt} = now()`] : []),
    ].join(",\n    ")}
  where y.${r.id} = finish_ai_task_run.id and y.${r.status} = 'running'
  returning y.${r.task} into v_task;
  if not found then
    return false;
  end if;${
    task("chat")
      ? `
  if finish_ai_task_run.chat_id is not null then
    update ${tasks} x set ${t.chat} = finish_ai_task_run.chat_id where x.${t.id} = v_task and x.${t.chat} is null;
  end if;`
      : ""
  }
  return true;
end;
$$;
${serviceGrant(`${fn("finish_ai_task_run")}(uuid, boolean, text, uuid)`)}${mirrorSql}`;
}

// Version 1 ended task runs succeeded; version 2 uses completed, the word
// ai-chat and workflow runs use.
function upgradeRunStates(ctx: BlockSqlContext): string {
  if (!ctx.owns("runs")) {
    return "";
  }

  const runs = ctx.table("runs");
  const status = ctx.col("runs", "status");

  return `${replaceColumnCheck({
    table: runs,
    column: status,
    name: "ai_task_runs_status_check",
    expression: `${status} in (${RUN_STATES}, 'succeeded')`,
  })}
update ${runs} set ${status} = 'completed' where ${status} = 'succeeded';
${replaceColumnCheck({
  table: runs,
  column: status,
  name: "ai_task_runs_status_check",
  expression: `${status} in (${RUN_STATES})`,
})}`;
}

// Version 3 adds the columns that mark a task as another scheduler's.
function upgradeMirror(ctx: BlockSqlContext): string {
  if (
    !(
      ctx.owns("tasks") &&
      ctx.has("tasks", "source") &&
      ctx.has("tasks", "externalId")
    )
  ) {
    return "";
  }

  const tasks = ctx.table("tasks");

  return `alter table ${tasks} add column if not exists ${ctx.col("tasks", "source")} text not null default '${SELF_SOURCE}' check (length(${ctx.col("tasks", "source")}) between 1 and 64);
alter table ${tasks} add column if not exists ${ctx.col("tasks", "externalId")} text check (length(${ctx.col("tasks", "externalId")}) between 1 and 200);`;
}

export const AI_TASKS: BlockSqlDefinition = {
  name: "ai-schedules",
  scopes: ["tenant"],
  title: "AI scheduled tasks",
  description:
    "Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.",
  requires: ["memberships", "permissions"],
  integrates: ["agents", "ai-chat", "queue"],
  target: "schema",
  version: 3,
  names: NAMES,
  upgrades: [
    {
      from: 2,
      description:
        "Tasks gain source and external_id so another scheduler's tasks can be mirrored.",
      sql: upgradeMirror,
    },
    {
      from: 1,
      description: "Task runs end completed instead of succeeded.",
      sql: upgradeRunStates,
    },
  ],
  build,
};
