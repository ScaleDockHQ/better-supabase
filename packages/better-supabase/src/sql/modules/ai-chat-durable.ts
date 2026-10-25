import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import {
  raise,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  pageSize,
} from "../shared.ts";
import { approvalJson } from "./ai-chat-extras.ts";
import { harnessSandbox, harnessSandboxSave } from "./ai-chat-sandboxes.ts";
import {
  asText,
  assignments,
  rowJson,
  variableConflict,
  writtenPairs,
} from "./ai-chat-tables.ts";

function runJson(ctx: BlockSqlContext, row: string): string {
  return rowJson(ctx, "runs", row, [
    ["id", "id"],
    ["chat_id", "chat"],
    ["owner_id", "owner"],
    ["assistant_message_id", "message"],
    ["stream_id", "stream"],
    ["engine", "engine"],
    ["external_run_id", "externalRun"],
    ["model", "model"],
    ["status", "status"],
    ["usage", "usage"],
    ["cost_micro_usd", "cost"],
    ["error", "error"],
    ["started_at", "startedAt"],
    ["ended_at", "endedAt"],
  ]);
}

function stepJson(ctx: BlockSqlContext, row: string): string {
  return rowJson(ctx, "steps", row, [
    ["id", "id"],
    ["run_id", "run"],
    ["chat_id", "chat"],
    ["step_key", "key"],
    ["label", "label"],
    ["status", "status"],
    ["detail", "detail", "'{}'::jsonb"],
    ["started_at", "startedAt"],
    ["ended_at", "endedAt"],
  ]);
}

function harnessJson(
  ctx: BlockSqlContext,
  names: AiChatNames,
  row: string,
): string {
  const json = (keys: readonly (readonly [string, string])[]): string =>
    rowJson(ctx, "harness", row, keys).slice("jsonb_build_object(".length, -1);

  return `jsonb_build_object(${json([
    ["chat_id", "chat"],
    ["harness_id", "harness"],
    ["owner_id", "owner"],
    ["resume_state", "resume"],
    ["continue_state", "continue"],
  ])}, 'sandbox_id', ${harnessSandbox(ctx, names, row)}, ${json([
    ["status", "status"],
    ["lock_holder", "holder"],
    ["locked_until", "lockedUntil"],
    ["last_active_at", "lastActiveAt"],
    ["created_at", "createdAt"],
    ["updated_at", "updatedAt"],
  ])})`;
}

const serviceOnly = raise(
  "Only the server records this",
  "42501",
  "AI_CHAT_FORBIDDEN",
);

function runs(ctx: BlockSqlContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const r = names.c.runs;
  const a = names.c.approvals;
  const s = names.c.steps;

  const noRun = (arg: string): string =>
    raise("No run %", "P0002", "AI_RUN_NOT_FOUND", arg);

  const [stepColumns, stepValues] = writtenPairs(ctx, "steps", [
    ["run", `v_run.${r.id}`],
    ["chat", `v_run.${r.chat}`],
    ["owner", `v_run.${r.owner}`],
    ["key", "record_ai_run_step.step ->> 'key'"],
    [
      "label",
      "\n    coalesce(nullif(record_ai_run_step.step ->> 'label', ''), record_ai_run_step.step ->> 'key')",
    ],
    ["status", `\n    ${ctx.cast("steps", "status", "v_status")}`],
    ["detail", "v_detail"],
    ["endedAt", "case when v_status <> 'running' then now() end"],
  ]);

  return `-- One run, when the caller may read its chat.
create or replace function ${fn("get_ai_run")}(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run ${t.runs};
begin
  select * into v_run from ${t.runs} x where x.${r.id} = get_ai_run.run;
  if not found or not ${fn("ai_chat_can_read")}(v_run.${r.chat}) then
    ${noRun("get_ai_run.run")}
  end if;
  return ${runJson(ctx, "v_run")};
end;
$$;
${userGrant(`${fn("get_ai_run")}(uuid)`)}

-- Runs, newest first: a chat's when chat is set, else the caller's own
-- (every run for the service role). active keeps the unfinished ones.
create or replace function ${fn("list_ai_runs")}(chat uuid default null, active boolean default null, size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if list_ai_runs.chat is not null and not ${fn("ai_chat_can_read")}(list_ai_runs.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "list_ai_runs.chat")}
  end if;
  return (
    select coalesce(jsonb_agg(${runJson(ctx, "y")} order by y.${r.startedAt} desc), '[]'::jsonb)
    from (
      select * from ${t.runs} x
      where (
          case when list_ai_runs.chat is not null then x.${r.chat} = list_ai_runs.chat
          else ${SERVICE_CALLER} or x.${r.owner} = (select auth.uid()) end
        )
        and (
          list_ai_runs.active is null
          or (${asText(ctx, "runs", `x.${r.status}`)} in ('queued', 'running', 'cancel_requested')) = list_ai_runs.active
        )
      order by x.${r.startedAt} desc
      limit ${pageSize("list_ai_runs.size", 50, 200)}
    ) y
  );
end;
$$;
${userGrant(`${fn("list_ai_runs")}(uuid, boolean, integer)`)}

-- Records the durable engine's run id on a run claimed before the engine
-- started (the service role only).
create or replace function ${fn("attach_ai_run")}(run uuid, external_run_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  update ${t.runs} x set ${r.externalRun} = attach_ai_run.external_run_id
  where x.${r.id} = attach_ai_run.run;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${serviceGrant(`${fn("attach_ai_run")}(uuid, text)`)}

-- The caller's undecided approvals across chats, newest first, with the
-- chat's title: the approval inbox.
create or replace function ${fn("list_pending_ai_tool_approvals")}(size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(y.approval order by y.created desc), '[]'::jsonb)
  from (
    select ${approvalJson(ctx, "x")} || jsonb_build_object('chat_title', c.${ch.title}) as approval, x.${a.createdAt} as created
    from ${t.approvals} x
    join ${t.chats} c on c.${ch.id} = x.${a.chat}
    where x.${a.owner} = (select auth.uid()) and x.${a.decision} is null
    order by x.${a.createdAt} desc
    limit ${pageSize("list_pending_ai_tool_approvals.size", 50, 200)}
  ) y;
$$;
${userGrant(`${fn("list_pending_ai_tool_approvals")}(integer)`)}

-- Records one step of a run's progress (the service role only). step holds
-- key (the idempotency key), label, status and detail; a retry with the same
-- key updates the row and merges detail.
create or replace function ${fn("record_ai_run_step")}(run uuid, step jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "steps")}
declare
  v_run ${t.runs};
  v_row ${t.steps};
  v_status text := coalesce(record_ai_run_step.step ->> 'status', 'running');
  v_detail jsonb := coalesce(record_ai_run_step.step -> 'detail', '{}'::jsonb);
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  select * into v_run from ${t.runs} x where x.${r.id} = record_ai_run_step.run;
  if not found then
    ${noRun("record_ai_run_step.run")}
  end if;
  if nullif(record_ai_run_step.step ->> 'key', '') is null
    or v_status not in ('running', 'done', 'error', 'skipped')
    or jsonb_typeof(v_detail) <> 'object' then
    ${raise("A step needs a key, a status of running, done, error or skipped and an object detail", "22023", "AI_RUN_STEP_INVALID")}
  end if;
  insert into ${t.steps} (${stepColumns})
  values (
    ${stepValues.replaceAll(", \n", ",\n")}
  )
  on conflict (${s.run}, ${s.key}) do update set
    ${s.label} = coalesce(nullif(record_ai_run_step.step ->> 'label', ''), ${t.steps}.${s.label}),
    ${s.status} = excluded.${s.status},${assignments(ctx, "steps", [
      ["detail", () => `${t.steps}.${s.detail} || excluded.${s.detail}`],
    ])}
    ${s.endedAt} = case when ${asText(ctx, "steps", `excluded.${s.status}`)} <> 'running' then coalesce(${t.steps}.${s.endedAt}, now()) end
  returning * into v_row;
  perform ${fn("ai_chat_notify")}(v_run.${r.chat}, null, 'run.step', jsonb_build_object('runId', v_run.${r.id}, 'key', v_row.${s.key}, 'status', v_row.${s.status}), false);
  return ${stepJson(ctx, "v_row")};
end;
$$;
${serviceGrant(`${fn("record_ai_run_step")}(uuid, jsonb)`)}

-- A run's steps in the order they started.
create or replace function ${fn("list_ai_run_steps")}(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run ${t.runs};
begin
  select * into v_run from ${t.runs} x where x.${r.id} = list_ai_run_steps.run;
  if not found or not ${fn("ai_chat_can_read")}(v_run.${r.chat}) then
    ${noRun("list_ai_run_steps.run")}
  end if;
  return (
    select coalesce(jsonb_agg(${stepJson(ctx, "x")} order by x.${s.startedAt}, x.${s.id}), '[]'::jsonb)
    from ${t.steps} x where x.${s.run} = v_run.${r.id}
  );
end;
$$;
${userGrant(`${fn("list_ai_run_steps")}(uuid)`)}`;
}

function harness(ctx: BlockSqlContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const h = names.c.harness;

  const ensure = (name: string): string => `
  select * into v_chat from ${t.chats} x where x.${ch.id} = ${name}.chat;
  if not found then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", `${name}.chat`)}
  end if;
  insert into ${t.harness} (${h.chat}, ${h.harness}, ${h.owner})
  values (v_chat.${ch.id}, ${name}.harness, v_chat.${ch.owner})
  on conflict (${h.chat}, ${h.harness}) do nothing;
  select * into v_row from ${t.harness} x
  where x.${h.chat} = v_chat.${ch.id} and x.${h.harness} = ${name}.harness
  for update;`;

  const validHarness = (name: string): string => `
  if nullif(${name}.harness, '') is null then
    ${raise("A harness session needs a harness id", "22023", "AI_HARNESS_INVALID")}
  end if;`;

  return `-- A harness session's state, or null (the service role only). Experimental.
create or replace function ${fn("load_ai_harness_session")}(chat uuid, harness text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t.harness};
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  select * into v_row from ${t.harness} x
  where x.${h.chat} = load_ai_harness_session.chat and x.${h.harness} = load_ai_harness_session.harness;
  if not found then
    return null;
  end if;
  return ${harnessJson(ctx, names, "v_row")};
end;
$$;
${serviceGrant(`${fn("load_ai_harness_session")}(uuid, text)`)}

-- Saves a harness session (the service role only). fields may set
-- resume_state, continue_state, sandbox_id (with sandbox_provider) and
-- status; a key that is absent keeps its value. sandbox_id registers the
-- session's sandbox in ai_sandboxes, and null marks it stopped. A session
-- locked by another holder raises AI_HARNESS_LOCKED.
create or replace function ${fn("save_ai_harness_session")}(chat uuid, harness text, fields jsonb, holder text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "harness", "sandboxes")}
declare
  v_chat ${t.chats};
  v_row ${t.harness};
  v_status text := save_ai_harness_session.fields ->> 'status';
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;${validHarness("save_ai_harness_session")}
  if jsonb_typeof(save_ai_harness_session.fields) is distinct from 'object'
    or (v_status is not null and v_status not in ('active', 'idle', 'stopped', 'error')) then
    ${raise("fields must be an object and status active, idle, stopped or error", "22023", "AI_HARNESS_INVALID")}
  end if;${ensure("save_ai_harness_session")}
  if v_row.${h.lockedUntil} > now() and v_row.${h.holder} is distinct from save_ai_harness_session.holder then
    ${raise("Harness session % is locked", "55P03", "AI_HARNESS_LOCKED", "save_ai_harness_session.harness")}
  end if;
  update ${t.harness} x set
    ${h.resume} = case when save_ai_harness_session.fields ? 'resume_state' then save_ai_harness_session.fields -> 'resume_state' else x.${h.resume} end,${assignments(
      ctx,
      "harness",
      [
        [
          "continue",
          () =>
            `case when save_ai_harness_session.fields ? 'continue_state' then save_ai_harness_session.fields -> 'continue_state' else x.${h.continue} end`,
        ],
      ],
    )}
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again.
    ${h.status} = coalesce(${ctx.cast("harness", "status", "v_status")}, case when ${asText(ctx, "harness", `x.${h.status}`)} = 'idle' then ${ctx.cast("harness", "status", "'active'")} else x.${h.status} end),
    ${h.lastActiveAt} = now(),
    ${h.updatedAt} = now()
  where x.${h.chat} = v_row.${h.chat} and x.${h.harness} = v_row.${h.harness}
  returning * into v_row;${harnessSandboxSave(ctx, names, "save_ai_harness_session.fields")}
  return ${harnessJson(ctx, names, "v_row")};
end;
$$;
${serviceGrant(`${fn("save_ai_harness_session")}(uuid, text, jsonb, text)`)}

-- Takes a harness session's lock for ttl_seconds (the service role only):
-- true when the caller holds it, false when another holder does.
create or replace function ${fn("lock_ai_harness_session")}(chat uuid, harness text, holder text, ttl_seconds integer default 300)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "harness", "sandboxes")}
declare
  v_chat ${t.chats};
  v_row ${t.harness};
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;${validHarness("lock_ai_harness_session")}
  if nullif(lock_ai_harness_session.holder, '') is null
    or coalesce(lock_ai_harness_session.ttl_seconds, 0) not between 1 and 86400 then
    ${raise("A lock needs a holder and a ttl between 1 and 86400 seconds", "22023", "AI_HARNESS_INVALID")}
  end if;${ensure("lock_ai_harness_session")}
  if v_row.${h.lockedUntil} > now() and v_row.${h.holder} is distinct from lock_ai_harness_session.holder then
    return false;
  end if;
  update ${t.harness} x set
    ${h.holder} = lock_ai_harness_session.holder,
    ${h.lockedUntil} = now() + make_interval(secs => lock_ai_harness_session.ttl_seconds),
    ${h.updatedAt} = now()
  where x.${h.chat} = v_row.${h.chat} and x.${h.harness} = v_row.${h.harness};
  return true;
end;
$$;
${serviceGrant(`${fn("lock_ai_harness_session")}(uuid, text, text, integer)`)}

-- Releases a harness session's lock when holder holds it (the service role only).
create or replace function ${fn("unlock_ai_harness_session")}(chat uuid, harness text, holder text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  update ${t.harness} x set ${h.holder} = null, ${h.lockedUntil} = null, ${h.updatedAt} = now()
  where x.${h.chat} = unlock_ai_harness_session.chat
    and x.${h.harness} = unlock_ai_harness_session.harness
    and x.${h.holder} = unlock_ai_harness_session.holder;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${serviceGrant(`${fn("unlock_ai_harness_session")}(uuid, text, text)`)}`;
}

/**
 * The SQL behind durable chat runs: run lookups for stop and resume, run steps
 * for progress, the approval inbox and the experimental harness session store.
 */
export function aiChatDurable(
  ctx: BlockSqlContext,
  names: AiChatNames,
): string {
  return `${runs(ctx, names)}

${harness(ctx, names)}`;
}
