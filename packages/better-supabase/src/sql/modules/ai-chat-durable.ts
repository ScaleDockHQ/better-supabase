import type { ModuleContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import {
  raise,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  pageSize,
} from "../shared.ts";
import { approvalJson } from "./ai-chat-extras.ts";

function runJson(names: AiChatNames, row: string): string {
  const r = names.c.runs;
  const keys: readonly (readonly [string, string])[] = [
    ["id", r.id],
    ["chat_id", r.chat],
    ["owner_id", r.owner],
    ["assistant_message_id", r.message],
    ["stream_id", r.stream],
    ["engine", r.engine],
    ["external_run_id", r.externalRun],
    ["model", r.model],
    ["status", r.status],
    ["usage", r.usage],
    ["cost_micro_usd", r.cost],
    ["error", r.error],
    ["started_at", r.startedAt],
    ["ended_at", r.endedAt],
  ];
  return `jsonb_build_object(${keys.map(([key, column]) => `'${key}', ${row}.${column}`).join(", ")})`;
}

function stepJson(names: AiChatNames, row: string): string {
  const s = names.c.steps;
  return `jsonb_build_object('id', ${row}.${s.id}, 'run_id', ${row}.${s.run}, 'chat_id', ${row}.${s.chat}, 'step_key', ${row}.${s.key}, 'label', ${row}.${s.label}, 'status', ${row}.${s.status}, 'detail', ${row}.${s.detail}, 'started_at', ${row}.${s.startedAt}, 'ended_at', ${row}.${s.endedAt})`;
}

function harnessJson(names: AiChatNames, row: string): string {
  const h = names.c.harness;
  return `jsonb_build_object('chat_id', ${row}.${h.chat}, 'harness_id', ${row}.${h.harness}, 'owner_id', ${row}.${h.owner}, 'resume_state', ${row}.${h.resume}, 'continue_state', ${row}.${h.continue}, 'sandbox_id', ${row}.${h.sandbox}, 'status', ${row}.${h.status}, 'lock_holder', ${row}.${h.holder}, 'locked_until', ${row}.${h.lockedUntil}, 'last_active_at', ${row}.${h.lastActiveAt}, 'created_at', ${row}.${h.createdAt}, 'updated_at', ${row}.${h.updatedAt})`;
}

const serviceOnly = raise(
  "Only the server records this",
  "42501",
  "AI_CHAT_FORBIDDEN",
);

function runs(ctx: ModuleContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const r = names.c.runs;
  const a = names.c.approvals;
  const s = names.c.steps;
  const noRun = (arg: string): string =>
    raise("No run %", "P0002", "AI_RUN_NOT_FOUND", arg);

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
  return ${runJson(names, "v_run")};
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
    select coalesce(jsonb_agg(${runJson(names, "y")} order by y.${r.startedAt} desc), '[]'::jsonb)
    from (
      select * from ${t.runs} x
      where (
          case when list_ai_runs.chat is not null then x.${r.chat} = list_ai_runs.chat
          else ${SERVICE_CALLER} or x.${r.owner} = (select auth.uid()) end
        )
        and (
          list_ai_runs.active is null
          or (x.${r.status} in ('queued', 'running', 'cancel_requested')) = list_ai_runs.active
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
    select ${approvalJson(names, "x")} || jsonb_build_object('chat_title', c.${ch.title}) as approval, x.${a.createdAt} as created
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
#variable_conflict use_variable
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
  insert into ${t.steps} (${s.run}, ${s.chat}, ${s.owner}, ${s.key}, ${s.label}, ${s.status}, ${s.detail}, ${s.endedAt})
  values (
    v_run.${r.id}, v_run.${r.chat}, v_run.${r.owner}, record_ai_run_step.step ->> 'key',
    coalesce(nullif(record_ai_run_step.step ->> 'label', ''), record_ai_run_step.step ->> 'key'),
    v_status, v_detail, case when v_status <> 'running' then now() end
  )
  on conflict (${s.run}, ${s.key}) do update set
    ${s.label} = coalesce(nullif(record_ai_run_step.step ->> 'label', ''), ${t.steps}.${s.label}),
    ${s.status} = excluded.${s.status},
    ${s.detail} = ${t.steps}.${s.detail} || excluded.${s.detail},
    ${s.endedAt} = case when excluded.${s.status} <> 'running' then coalesce(${t.steps}.${s.endedAt}, now()) end
  returning * into v_row;
  perform ${fn("ai_chat_notify")}(v_run.${r.chat}, null, 'run.step', jsonb_build_object('runId', v_run.${r.id}, 'key', v_row.${s.key}, 'status', v_row.${s.status}), false);
  return ${stepJson(names, "v_row")};
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
    select coalesce(jsonb_agg(${stepJson(names, "x")} order by x.${s.startedAt}, x.${s.id}), '[]'::jsonb)
    from ${t.steps} x where x.${s.run} = v_run.${r.id}
  );
end;
$$;
${userGrant(`${fn("list_ai_run_steps")}(uuid)`)}`;
}

function harness(ctx: ModuleContext, names: AiChatNames): string {
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
  return ${harnessJson(names, "v_row")};
end;
$$;
${serviceGrant(`${fn("load_ai_harness_session")}(uuid, text)`)}

-- Saves a harness session (the service role only). fields may set
-- resume_state, continue_state, sandbox_id and status; a key that is absent
-- keeps its value. A session locked by another holder raises
-- AI_HARNESS_LOCKED.
create or replace function ${fn("save_ai_harness_session")}(chat uuid, harness text, fields jsonb, holder text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
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
    ${h.resume} = case when save_ai_harness_session.fields ? 'resume_state' then save_ai_harness_session.fields -> 'resume_state' else x.${h.resume} end,
    ${h.continue} = case when save_ai_harness_session.fields ? 'continue_state' then save_ai_harness_session.fields -> 'continue_state' else x.${h.continue} end,
    ${h.sandbox} = case when save_ai_harness_session.fields ? 'sandbox_id' then save_ai_harness_session.fields ->> 'sandbox_id' else x.${h.sandbox} end,
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again, so a later idle_ai_harness_sessions finds it.
    ${h.status} = coalesce(v_status, case when x.${h.status} = 'idle' then 'active' else x.${h.status} end),
    ${h.lastActiveAt} = now(),
    ${h.updatedAt} = now()
  where x.${h.chat} = v_row.${h.chat} and x.${h.harness} = v_row.${h.harness}
  returning * into v_row;
  return ${harnessJson(names, "v_row")};
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
#variable_conflict use_variable
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
${serviceGrant(`${fn("unlock_ai_harness_session")}(uuid, text, text)`)}

-- Marks active sessions whose sandbox sat unused for idle_seconds as idle
-- and returns them, so a job stops their sandboxes (the service role only).
-- Locked sessions are skipped.
create or replace function ${fn("idle_ai_harness_sessions")}(idle_seconds integer default 900, size integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_result jsonb;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  with picked as (
    select x.${h.chat}, x.${h.harness} from ${t.harness} x
    where x.${h.status} = 'active' and x.${h.sandbox} is not null
      and x.${h.lastActiveAt} < now() - make_interval(secs => greatest(coalesce(idle_ai_harness_sessions.idle_seconds, 900), 1))
      and (x.${h.lockedUntil} is null or x.${h.lockedUntil} <= now())
    order by x.${h.lastActiveAt}
    limit ${pageSize("idle_ai_harness_sessions.size", 100, 1000)}
    for update skip locked
  ), marked as (
    update ${t.harness} x set ${h.status} = 'idle', ${h.updatedAt} = now()
    from picked
    where x.${h.chat} = picked.${h.chat} and x.${h.harness} = picked.${h.harness}
    returning x.*
  )
  select coalesce(jsonb_agg(${harnessJson(names, "marked")}), '[]'::jsonb) into v_result from marked;
  return v_result;
end;
$$;
${serviceGrant(`${fn("idle_ai_harness_sessions")}(integer, integer)`)}`;
}

/**
 * The SQL behind durable chat runs: run lookups for stop and resume, run
 * steps for progress, the approval inbox and the experimental harness
 * session store.
 */
export function aiChatDurable(ctx: ModuleContext, names: AiChatNames): string {
  return `${runs(ctx, names)}

${harness(ctx, names)}`;
}
