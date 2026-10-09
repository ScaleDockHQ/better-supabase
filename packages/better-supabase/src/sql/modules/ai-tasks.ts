import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import {
  canIn,
  raise,
  replaceColumnCheck,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  tenantIn,
  userGrant,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { columnsOf, rowJson } from "./module-columns.ts";

const RUN_STATES = "'queued', 'running', 'completed', 'failed'";

const TASKS = {
  id: "id",
  tenant: "organization_id",
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
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const RUNS = {
  id: "id",
  task: "task_id",
  tenant: "organization_id",
  user: "user_id",
  status: "status",
  scheduledFor: "scheduled_for",
  chat: "chat_id",
  error: "error",
  startedAt: "started_at",
  finishedAt: "finished_at",
  createdAt: "created_at",
} as const;

const NAMES: ModuleNames = {
  options: ["queue", "staleAfter", "maxPrompt"],
  tables: {
    tasks: {
      name: "ai_scheduled_tasks",
      columns: TASKS,
      lifecycle: { user: "user", tenant: "tenant" },
    },
    runs: {
      name: "ai_task_runs",
      columns: RUNS,
      lifecycle: { user: "user", tenant: "tenant" },
    },
  },
};

const QUEUE = /^[a-z_][a-z0-9_]{0,46}$/;
const INTERVAL = /^\d+ (second|minute|hour|day)s?$/;

function build(ctx: ModuleContext): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = columnsOf(ctx, "tasks", TASKS);
  const r = columnsOf(ctx, "runs", RUNS);
  const tasks = ctx.table("tasks");
  const runs = ctx.table("runs");
  const permissions = MODULE_PERMISSIONS["ai-tasks"];
  const create = ctx.permission("create", permissions.create);
  const manage = ctx.permission("manage", permissions.manage);
  const maxPrompt = ctx.number("maxPrompt", 20000);
  const queue = ctx.text("queue", "ai_task_run");
  if (!QUEUE.test(queue)) {
    throw new TypeError(
      "sql.modules.ai-tasks.options.queue must be a lowercase queue name of at most 47 characters",
    );
  }
  const staleAfter = ctx.text("staleAfter", "30 minutes");
  if (!INTERVAL.test(staleAfter)) {
    throw new TypeError(
      'sql.modules.ai-tasks.options.staleAfter must be an interval such as "30 minutes"',
    );
  }
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
  const taskJson = (row: string): string => rowJson(TASKS, t, row);
  const runJson = (row: string): string => rowJson(RUNS, r, row);
  const enqueue = (run: string): string =>
    ctx.installed("jobs")
      ? `
    ${ctx.enqueue(queue, `jsonb_build_object('run_id', ${run})`, `'ai-task:' || ${run}::text`)}`
      : "";
  const mayEdit = (row: string): string =>
    `(${SERVICE_CALLER} or ${row}.${t.user} = auth.uid() or ${canIn(`${row}.${t.tenant}`, manage)})`;
  const notFound = raise(
    "task % not found",
    "P0002",
    "AI_TASK_NOT_FOUND",
    "v_id",
  );

  return `${schemaPreamble(ctx)}
-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table if not exists ${tasks} (
  ${t.id} uuid primary key default gen_random_uuid(),
  ${t.tenant} ${id} not null,
  ${t.user} uuid not null references auth.users (id) on delete cascade,
  ${t.chat} uuid,
  ${t.agent} uuid${agentReference},
  ${t.title} text not null check (length(${t.title}) between 1 and 200),
  ${t.prompt} text not null check (length(${t.prompt}) between 1 and ${maxPrompt}),
  ${t.cron} text not null check (length(${t.cron}) between 1 and 200),
  ${t.timezone} text not null default 'UTC' check (length(${t.timezone}) between 1 and 64),
  ${t.enabled} boolean not null default true,
  ${t.nextRunAt} timestamptz,
  ${t.lastRunAt} timestamptz,
  ${t.createdAt} timestamptz not null default now(),
  ${t.updatedAt} timestamptz not null default now()
);
create index if not exists ai_scheduled_tasks_due_idx on ${tasks} (${t.nextRunAt}) where ${t.enabled};
create index if not exists ai_scheduled_tasks_user_idx on ${tasks} (${t.user}, ${t.tenant});
create index if not exists ai_scheduled_tasks_agent_idx on ${tasks} (${t.agent});
alter table ${tasks} enable row level security;
revoke all on ${tasks} from anon, authenticated;
grant select on ${tasks} to authenticated;
grant all on ${tasks} to service_role;
drop policy if exists ai_scheduled_tasks_read on ${tasks};
create policy ai_scheduled_tasks_read on ${tasks} for select to authenticated
  using (${t.user} = (select auth.uid()) or ${tenantIn(t.tenant, manage)});

create table if not exists ${runs} (
  ${r.id} uuid primary key default gen_random_uuid(),
  ${r.task} uuid not null references ${tasks} (${t.id}) on delete cascade,
  ${r.tenant} ${id} not null,
  ${r.user} uuid not null references auth.users (id) on delete cascade,
  ${r.status} text not null default 'queued' check (${r.status} in (${RUN_STATES})),
  ${r.scheduledFor} timestamptz not null,
  ${r.chat} uuid,
  ${r.error} text check (length(${r.error}) <= 4000),
  ${r.startedAt} timestamptz,
  ${r.finishedAt} timestamptz,
  ${r.createdAt} timestamptz not null default now()
);
create index if not exists ai_task_runs_task_idx on ${runs} (${r.task}, ${r.createdAt} desc);
create index if not exists ai_task_runs_user_idx on ${runs} (${r.user});
create index if not exists ai_task_runs_open_idx on ${runs} (${r.status}, ${r.startedAt}) where ${r.status} in ('queued', 'running');
alter table ${runs} enable row level security;
revoke all on ${runs} from anon, authenticated;
grant select on ${runs} to authenticated;
grant all on ${runs} to service_role;
drop policy if exists ai_task_runs_read on ${runs};
create policy ai_task_runs_read on ${runs} for select to authenticated
  using (${r.user} = (select auth.uid()) or ${tenantIn(r.tenant, manage)});

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
    if not (${SERVICE_CALLER} or ${canIn("save_ai_task.tenant", create)}) or auth.uid() is null then
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
    ${t.timezone} = coalesce(save_ai_task.fields ->> 'timezone', x.${t.timezone}),
    ${t.chat} = case when save_ai_task.fields ? 'chat_id' then (save_ai_task.fields ->> 'chat_id')::uuid else x.${t.chat} end,
    ${t.agent} = case when save_ai_task.fields ? 'agent_id' then (save_ai_task.fields ->> 'agent_id')::uuid else x.${t.agent} end,
    ${t.enabled} = coalesce((save_ai_task.fields ->> 'enabled')::boolean, x.${t.enabled}),
    ${t.nextRunAt} = case
      when (save_ai_task.fields ->> 'enabled')::boolean is false then null
      when v_service and (save_ai_task.next_run_at is not null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone') then save_ai_task.next_run_at
      when save_ai_task.id is null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone' then null
      else x.${t.nextRunAt} end,
    ${t.updatedAt} = now()
  where x.${t.id} = v_row.${t.id}
  returning * into v_row;
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
  update ${runs} y set ${r.status} = 'failed', ${r.error} = 'timed out', ${r.finishedAt} = now()
  where (y.${r.status} = 'running' and y.${r.startedAt} < now() - interval '${staleAfter}')
     or (y.${r.status} = 'queued' and y.${r.createdAt} < now() - interval '${staleAfter}');
  for v_task in
    select * from ${tasks} x
    where x.${t.enabled} and x.${t.nextRunAt} <= now()
    order by x.${t.nextRunAt}
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into ${runs} (${r.task}, ${r.tenant}, ${r.user}, ${r.scheduledFor}, ${r.chat})
    values (v_task.${t.id}, v_task.${t.tenant}, v_task.${t.user}, v_task.${t.nextRunAt}, v_task.${t.chat})
    returning * into v_run;
    update ${tasks} x set ${t.nextRunAt} = null, ${t.lastRunAt} = now() where x.${t.id} = v_task.${t.id};${enqueue(`v_run.${r.id}`)}
    v_runs := v_runs || jsonb_build_array(${runJson("v_run")});
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${t.id}, 'cron', x.${t.cron}, 'timezone', x.${t.timezone})), '[]')
  into v_unscheduled
  from ${tasks} x where x.${t.enabled} and x.${t.nextRunAt} is null;
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
  where x.${t.id} = (item ->> 'id')::uuid and x.${t.enabled} and x.${t.nextRunAt} is null;
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
  update ${runs} y set ${r.status} = 'running', ${r.startedAt} = now()
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
    ${r.status} = case when finish_ai_task_run.succeeded then 'completed' else 'failed' end,
    ${r.error} = left(finish_ai_task_run.error, 4000),
    ${r.chat} = coalesce(finish_ai_task_run.chat_id, y.${r.chat}),
    ${r.finishedAt} = now()
  where y.${r.id} = finish_ai_task_run.id and y.${r.status} = 'running'
  returning y.${r.task} into v_task;
  if not found then
    return false;
  end if;
  if finish_ai_task_run.chat_id is not null then
    update ${tasks} x set ${t.chat} = finish_ai_task_run.chat_id where x.${t.id} = v_task and x.${t.chat} is null;
  end if;
  return true;
end;
$$;
${serviceGrant(`${fn("finish_ai_task_run")}(uuid, boolean, text, uuid)`)}`;
}

// Task runs end completed since 0.7, the word ai-chat and workflow runs use.
function upgradeRunStates(ctx: ModuleContext): string {
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

export const AI_TASKS: ModuleDefinition = {
  name: "ai-tasks",
  title: "AI scheduled tasks",
  description:
    "Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.",
  requires: ["tenant", "access"],
  integrates: ["agents", "ai-chat", "jobs"],
  target: "schema",
  version: 2,
  names: NAMES,
  upgrades: [
    {
      from: 1,
      description: "Task runs end completed instead of succeeded.",
      sql: upgradeRunStates,
    },
  ],
  build,
};
