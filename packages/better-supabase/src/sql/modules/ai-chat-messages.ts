import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { FINAL_RUN_STATES as FINAL } from "../../core/run-state.ts";
import { sqlString } from "../../core/template.ts";
import { raise, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import {
  asText,
  assignments,
  columnOr,
  rowJson,
  variableConflict,
  writtenPairs,
} from "./ai-chat-tables.ts";
import { metersOf } from "./usage-meters.ts";

const FINAL_RUN_STATES = FINAL.map(sqlString).join(", ");

function messageJson(
  ctx: BlockSqlContext,
  row: string,
  native: string,
): string {
  const nativeJson = ctx.has("messages", "native")
    ? `case when ${native} then ${columnOr(ctx, "messages", row, "native")} end`
    : "null";

  return rowJson(
    ctx,
    "messages",
    row,
    [
      ["id", "id"],
      ["parent_id", "parent"],
      ["role", "role"],
      ["parts", "parts"],
      ["metadata", "metadata", "'{}'::jsonb"],
      ["format", "format", "'canonical'"],
    ],
    `, 'native', ${nativeJson}, ${["model", "status", "createdAt"]
      .map(
        (column, index) =>
          `'${["model", "status", "created_at"][index]}', ${columnOr(ctx, "messages", row, column)}`,
      )
      .join(", ")}`,
  );
}

const METER = /^[a-z][a-z0-9_.:-]{0,63}$/;

/**
 * PL/pgSQL that records a released run's tokens on the usage meters
 * (`options.inputMeter`, `options.outputMeter`), once per run. Empty without
 * the usage block or with `options.meterUsage: false`. With a meter catalog
 * (`blocks.usage.options.meters`) a meter it lacks is skipped, not an error.
 */
function runMetering(ctx: BlockSqlContext, names: AiChatNames): string {
  if (!ctx.installed("usage") || !ctx.flag("meterUsage", true)) {
    return "";
  }

  const usage = ctx.of("usage");
  const catalog = metersOf(usage) !== undefined;
  const ch = names.c.chats;

  const meter = (option: string, fallback: string, key: string): string => {
    const name = ctx.text(option, fallback);

    if (!METER.test(name)) {
      throw new TypeError(
        `blocks.ai-chat.options.${option}: "${name}" is not a meter name`,
      );
    }

    const quantity = `v_usage -> ${sqlString(key)}`;

    return `
    if jsonb_typeof(${quantity}) = 'number' and (${quantity})::numeric > 0${catalog ? ` and ${usage.fn("usage_meters")}() ? ${sqlString(name)}` : ""} then
      perform ${usage.fn("record_usage")}(v_tenant, ${sqlString(name)}, (${quantity})::numeric, 'ai_run:' || v_run || ':' || ${sqlString(key)}, 'ai-chat', jsonb_build_object('chatId', release_ai_chat_stream.chat, 'runId', v_run), v_owner);
    end if;`;
  };

  return `
  if v_run is not null and jsonb_typeof(v_usage) = 'object' then
    select x.${ch.tenant} into v_tenant from ${names.t.chats} x where x.${ch.id} = release_ai_chat_stream.chat;
    if v_tenant is not null then${meter("inputMeter", "ai.input_tokens", "inputTokens")}${meter("outputMeter", "ai.output_tokens", "outputTokens")}
    end if;
  end if;`;
}

/**
 * The message tree, the reply stream claim and run costs of the `ai-chat`
 * module.
 */
export function aiChatMessages(
  ctx: BlockSqlContext,
  names: AiChatNames,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const m = names.c.messages;
  const r = names.c.runs;
  const s = names.c.sources;
  const streams = ctx.of("streams");
  const st = (column: string): string => streams.col("streams", column);

  const ownChat = (name: string): string => `
  select * into v_chat from ${t.chats} x where x.${ch.id} = ${name}.chat for update;
  if not found or not (${SERVICE_CALLER} or coalesce(v_chat.${ch.owner} = (select auth.uid()), false)) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", `${name}.chat`)}
  end if;`;

  const metering = runMetering(ctx, names);

  const role = (row: string): string =>
    asText(ctx, "messages", `${row}.${m.role}`);

  const runStatus = (row: string): string =>
    asText(ctx, "runs", `${row}.${r.status}`);

  const message = (
    pairs: readonly (readonly [string, string])[],
  ): readonly [string, string] =>
    writtenPairs(ctx, "messages", [
      ...pairs,
      ...(ctx.owns("messages") || pairs.some(([column]) => column === "status")
        ? []
        : ([
            ["status", ctx.cast("messages", "status", "'complete'")],
          ] as const)),
    ]);

  const [userColumns, userValues] = message([
    ["chat", `\n    v_chat.${ch.id}`],
    ["id", "v_id"],
    ["parent", "v_parent"],
    ["owner", `v_chat.${ch.owner}`],
    ["role", ctx.cast("messages", "role", "'user'")],
    ["parts", "append_ai_user_message.message -> 'parts'"],
    [
      "metadata",
      "\n    case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else '{}'::jsonb end",
    ],
  ]);

  const [replyColumns, replyValues] = message([
    ["chat", `\n    v_chat.${ch.id}`],
    ["id", "v_id"],
    ["parent", "save_ai_assistant_message.parent_id"],
    ["owner", `v_chat.${ch.owner}`],
    ["role", ctx.cast("messages", "role", "v_role")],
    ["parts", "\n    save_ai_assistant_message.message -> 'parts'"],
    [
      "metadata",
      "\n    case when jsonb_typeof(save_ai_assistant_message.message -> 'metadata') = 'object' then save_ai_assistant_message.message -> 'metadata' else '{}'::jsonb end",
    ],
    ["format", "\n    coalesce(save_ai_assistant_message.format, 'canonical')"],
    ["native", "save_ai_assistant_message.native"],
    ["model", "\n    save_ai_assistant_message.model"],
    ["status", ctx.cast("messages", "status", "v_status")],
  ]);

  const [sourceColumns, sourceValues] = writtenPairs(ctx, "sources", [
    ["chat", `v_chat.${ch.id}`],
    ["message", "v_id"],
    ["source", "e ->> 'id'"],
    [
      "kind",
      ctx.cast("sources", "kind", "coalesce(e ->> 'sourceType', 'url')"),
    ],
    ["url", "e ->> 'url'"],
    ["title", "e ->> 'title'"],
    ["metadata", "e -> 'providerMetadata'"],
  ]);

  const [runColumns, runValues] = writtenPairs(ctx, "runs", [
    ["chat", `v_chat.${ch.id}`],
    ["owner", `v_chat.${ch.owner}`],
    ["message", "claim_ai_chat_stream.message_id"],
    ["stream", "claim_ai_chat_stream.stream"],
    ["engine", "coalesce(claim_ai_chat_stream.engine, 'ai-sdk')"],
    ["externalRun", "claim_ai_chat_stream.external_run_id"],
    ["model", `coalesce(claim_ai_chat_stream.model, v_chat.${ch.model})`],
    ...(ctx.owns("runs")
      ? []
      : ([["status", ctx.cast("runs", "status", "'running'")]] as const)),
  ]);

  const serviceOnly = raise(
    "Only the server saves replies",
    "42501",
    "AI_CHAT_FORBIDDEN",
  );

  const completed = ctx.record({
    type: "ai_chat_message.completed",
    payload: `jsonb_build_object('chatId', v_chat.${ch.id}, 'messageId', v_id, 'organizationId', v_chat.${ch.tenant}::text, 'ownerId', v_chat.${ch.owner}, 'model', coalesce(save_ai_assistant_message.model, v_chat.${ch.model}), 'status', v_status)`,
    subject: `'ai-chats/' || v_chat.${ch.id}::text`,
    tenant: `v_chat.${ch.tenant}`,
    key: `'ai_chat_message.completed:' || v_chat.${ch.id}::text || ':' || v_id`,
    audit: false,
  });

  return `-- The branch that ends at leaf, root first, with each message's place among
-- its siblings (sibling_index of sibling_count) for the "2 / 3" arrows. No
-- permission check: callers check first.
create or replace function ${fn("ai_message_path_of")}(chat uuid, leaf text, include_native boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive up as (
    select x.*, 0 as depth from ${t.messages} x
    where x.${m.chat} = ai_message_path_of.chat and x.${m.id} = ai_message_path_of.leaf
    union all
    select x.*, up.depth + 1 from ${t.messages} x
    join up on x.${m.chat} = up.${m.chat} and x.${m.id} = up.${m.parent}
    where up.depth < 10000
  )
  select coalesce(jsonb_agg(
    ${messageJson(ctx, "up", "ai_message_path_of.include_native")} || jsonb_build_object(
      'sibling_count', (select count(*) from ${t.messages} sb where sb.${m.chat} = up.${m.chat} and sb.${m.parent} is not distinct from up.${m.parent}),
      'sibling_index', (select count(*) from ${t.messages} sb where sb.${m.chat} = up.${m.chat} and sb.${m.parent} is not distinct from up.${m.parent} and sb.${m.seq} < up.${m.seq})
    )
    order by up.depth desc
  ), '[]'::jsonb)
  from up;
$$;
revoke execute on function ${fn("ai_message_path_of")}(uuid, text, boolean) from public, anon, authenticated;

-- The branch the chat shows (or the one ending at leaf), root first.
create or replace function ${fn("ai_message_path")}(chat uuid, leaf text default null, include_native boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_leaf text;
begin
  if not ${fn("ai_chat_can_read")}(ai_message_path.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "ai_message_path.chat")}
  end if;
  select coalesce(ai_message_path.leaf, x.${ch.leaf}) into v_leaf from ${t.chats} x where x.${ch.id} = ai_message_path.chat;
  if v_leaf is null then
    return '[]'::jsonb;
  end if;
  return ${fn("ai_message_path_of")}(ai_message_path.chat, v_leaf, coalesce(ai_message_path.include_native, false));
end;
$$;
${userGrant(`${fn("ai_message_path")}(uuid, text, boolean)`)}

-- The versions of a message (same parent), oldest first.
create or replace function ${fn("ai_message_siblings")}(chat uuid, message_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parent text;
begin
  if not ${fn("ai_chat_can_read")}(ai_message_siblings.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "ai_message_siblings.chat")}
  end if;
  select x.${m.parent} into v_parent from ${t.messages} x
  where x.${m.chat} = ai_message_siblings.chat and x.${m.id} = ai_message_siblings.message_id;
  if not found then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "ai_message_siblings.message_id")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x.${m.id}, 'role', x.${m.role}, 'created_at', x.${m.createdAt}) order by x.${m.seq}), '[]'::jsonb)
    from ${t.messages} x
    where x.${m.chat} = ai_message_siblings.chat and x.${m.parent} is not distinct from v_parent
  );
end;
$$;
${userGrant(`${fn("ai_message_siblings")}(uuid, text)`)}

-- Shows the branch through message_id: the chat's leaf becomes the newest
-- descendant of message_id, following the latest child at each turn.
create or replace function ${fn("switch_ai_branch")}(chat uuid, message_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat ${t.chats};
  v_leaf text;
begin${ownChat("switch_ai_branch")}
  if not exists (select 1 from ${t.messages} x where x.${m.chat} = switch_ai_branch.chat and x.${m.id} = switch_ai_branch.message_id) then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "switch_ai_branch.message_id")}
  end if;
  with recursive down as (
    select switch_ai_branch.message_id as id, 0 as depth
    union all
    select (
      select c.${m.id} from ${t.messages} c
      where c.${m.chat} = switch_ai_branch.chat and c.${m.parent} = down.id
      order by c.${m.seq} desc limit 1
    ), down.depth + 1
    from down
    where down.id is not null and down.depth < 10000
  )
  select d.id into v_leaf from down d where d.id is not null order by d.depth desc limit 1;
  update ${t.chats} x set ${ch.leaf} = v_leaf, ${ch.updatedAt} = now() where x.${ch.id} = switch_ai_branch.chat;
  perform ${fn("ai_chat_notify")}(switch_ai_branch.chat, null, 'leaf.changed', jsonb_build_object('leafId', v_leaf), false);
  return jsonb_build_object('leaf_id', v_leaf);
end;
$$;
${userGrant(`${fn("switch_ai_branch")}(uuid, text)`)}

-- Stores the user's message. trigger 'submit-message' appends message under
-- the chat's leaf, or, with message_id, as a new version of that message.
-- The id is the client's, so a retry with the same parts is a no-op; the
-- same id with other parts is an edit and gets a fresh id. trigger
-- 'regenerate-message' stores nothing and moves the leaf to the user
-- message whose reply is regenerated. Returns { message_id, parent_id,
-- created }; the reply goes under message_id (or parent_id on regenerate).
create or replace function ${fn("append_ai_user_message")}(chat uuid, message jsonb, trigger text default 'submit-message', message_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat ${t.chats};
  v_existing ${t.messages};
  v_id text;
  v_parent text;
  v_target text;
begin${ownChat("append_ai_user_message")}
  if coalesce(append_ai_user_message.trigger, 'submit-message') = 'regenerate-message' then
    v_target := coalesce(append_ai_user_message.message_id, v_chat.${ch.leaf});
    select * into v_existing from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_target;
    if not found then
      ${raise("No message % to regenerate", "P0002", "AI_MESSAGE_NOT_FOUND", "v_target")}
    end if;
    v_parent := case when ${role("v_existing")} = 'user' then v_existing.${m.id} else v_existing.${m.parent} end;
    update ${t.chats} x set ${ch.leaf} = v_parent, ${ch.updatedAt} = now() where x.${ch.id} = v_chat.${ch.id};
    perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, null, 'leaf.changed', jsonb_build_object('leafId', v_parent), false);
    return jsonb_build_object('message_id', v_parent, 'parent_id', v_parent, 'created', false);
  elsif append_ai_user_message.trigger <> 'submit-message' then
    ${raise("Unknown trigger %", "22023", "AI_MESSAGE_INVALID", "append_ai_user_message.trigger")}
  end if;
  if jsonb_typeof(append_ai_user_message.message) is distinct from 'object'
    or append_ai_user_message.message ->> 'role' is distinct from 'user'
    or nullif(append_ai_user_message.message ->> 'id', '') is null
    or jsonb_typeof(append_ai_user_message.message -> 'parts') is distinct from 'array' then
    ${raise("A user message needs an id, role user and parts", "22023", "AI_MESSAGE_INVALID")}
  end if;
  v_id := append_ai_user_message.message ->> 'id';
  select * into v_existing from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_id;
  if found then
    if v_existing.${m.parts} = append_ai_user_message.message -> 'parts' then
      return jsonb_build_object('message_id', v_id, 'parent_id', v_existing.${m.parent}, 'created', false);
    end if;
    v_parent := v_existing.${m.parent};
    v_id := gen_random_uuid()::text;
  elsif append_ai_user_message.message_id is not null then
    select x.${m.parent} into v_parent from ${t.messages} x
    where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = append_ai_user_message.message_id;
    if not found then
      ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "append_ai_user_message.message_id")}
    end if;
  else
    v_parent := v_chat.${ch.leaf};
  end if;
  insert into ${t.messages} (${userColumns})
  values (${userValues}
  );
  update ${t.chats} x set ${ch.leaf} = v_id, ${ch.lastMessageAt} = clock_timestamp(), ${ch.updatedAt} = now() where x.${ch.id} = v_chat.${ch.id};
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, v_chat.${ch.owner}, 'message.saved', jsonb_build_object('messageId', v_id), not v_chat.${ch.temporary});
  return jsonb_build_object('message_id', v_id, 'parent_id', v_parent, 'created', true);
end;
$$;
${userGrant(`${fn("append_ai_user_message")}(uuid, jsonb, text, text)`)}

-- Stores a reply under parent_id (the service role only): an upsert by id, so
-- the server saves once at the end and again after a resumed stream. Copies
-- source parts to ${t.sources} and moves the leaf to the reply.
create or replace function ${fn("save_ai_assistant_message")}(chat uuid, message jsonb, parent_id text, status text default 'complete', model text default null, format text default 'canonical', native jsonb default null, run uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "messages", "sources", "chats", "runs")}
declare
  v_chat ${t.chats};
  v_id text := save_ai_assistant_message.message ->> 'id';
  v_role text := coalesce(save_ai_assistant_message.message ->> 'role', 'assistant');
  v_status text := coalesce(save_ai_assistant_message.status, 'complete');
  v_created boolean;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  select * into v_chat from ${t.chats} x where x.${ch.id} = save_ai_assistant_message.chat for update;
  if not found then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "save_ai_assistant_message.chat")}
  end if;
  if nullif(v_id, '') is null or v_role = 'user'
    or jsonb_typeof(save_ai_assistant_message.message -> 'parts') is distinct from 'array' then
    ${raise("A reply needs an id, a role other than user and parts", "22023", "AI_MESSAGE_INVALID")}
  end if;
  if save_ai_assistant_message.parent_id is not null and not exists (
    select 1 from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = save_ai_assistant_message.parent_id
  ) then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "save_ai_assistant_message.parent_id")}
  end if;
  insert into ${t.messages} (${replyColumns})
  values (${replyValues}
  )
  on conflict (${m.chat}, ${m.id}) do update set
    ${m.parts} = excluded.${m.parts},${assignments(ctx, "messages", [
      ["metadata", () => `excluded.${m.metadata}`],
      ["format", () => `excluded.${m.format}`],
      ["native", () => `excluded.${m.native}`],
      [
        "model",
        () => `coalesce(excluded.${m.model}, ${t.messages}.${m.model})`,
      ],
    ])}
    ${m.status} = excluded.${m.status}
  returning (xmax = 0) into v_created;
  delete from ${t.sources} x where x.${s.chat} = v_chat.${ch.id} and x.${s.message} = v_id;
  insert into ${t.sources} (${sourceColumns})
  select distinct on (e ->> 'id') ${sourceValues}
  from jsonb_array_elements(save_ai_assistant_message.message -> 'parts') e
  where e ->> 'type' = 'source' and nullif(e ->> 'id', '') is not null and coalesce(e ->> 'sourceType', 'url') in ('url', 'document')
  order by e ->> 'id';
  update ${t.chats} x set ${ch.leaf} = v_id, ${ch.lastMessageAt} = clock_timestamp(), ${ch.updatedAt} = now() where x.${ch.id} = v_chat.${ch.id};
  if save_ai_assistant_message.run is not null then
    update ${t.runs} x set ${r.message} = v_id where x.${r.id} = save_ai_assistant_message.run and x.${r.chat} = v_chat.${ch.id};
  end if;
  if v_status = 'complete' then
    ${completed}
  end if;
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, v_chat.${ch.owner}, 'message.saved', jsonb_build_object('messageId', v_id), not v_chat.${ch.temporary});
  return jsonb_build_object('message_id', v_id, 'parent_id', save_ai_assistant_message.parent_id, 'created', v_created);
end;
$$;
${serviceGrant(`${fn("save_ai_assistant_message")}(uuid, jsonb, text, text, text, text, jsonb, uuid)`)}

-- Claims the chat for one reply stream (the service role only). A claim
-- held by a run that ended, whose stream closed, or that started more than
-- ${names.staleAfter} ago is taken over. Returns { claimed, stream_id,
-- run_id }: the active stream when another reply holds the chat.
-- external_run_id is the durable engine's own run id, such as a Workflow
-- SDK run, so stop and resume can reach that run.
drop function if exists ${fn("claim_ai_chat_stream")}(uuid, text, text, text, text);
create or replace function ${fn("claim_ai_chat_stream")}(chat uuid, stream text, model text default null, message_id text default null, engine text default 'ai-sdk', external_run_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat ${t.chats};
  v_run ${t.runs};
  v_run_id uuid;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  select * into v_chat from ${t.chats} x where x.${ch.id} = claim_ai_chat_stream.chat for update;
  if not found then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "claim_ai_chat_stream.chat")}
  end if;
  if v_chat.${ch.activeStream} is not null then
    select * into v_run from ${t.runs} x where x.${r.id} = v_chat.${ch.activeRun};
    if v_chat.${ch.activeStream} = claim_ai_chat_stream.stream then
      return jsonb_build_object('claimed', true, 'stream_id', v_chat.${ch.activeStream}, 'run_id', v_chat.${ch.activeRun});
    end if;
    if v_run.${r.id} is not null
      and ${runStatus("v_run")} in ('queued', 'running', 'cancel_requested')
      and v_run.${r.startedAt} > now() - interval ${sqlString(names.staleAfter)}
      and not exists (
        select 1 from ${streams.table("streams")} so
        where so.${st("id")} = v_chat.${ch.activeStream} and so.${st("closedAt")} is not null
      ) then
      return jsonb_build_object('claimed', false, 'stream_id', v_chat.${ch.activeStream}, 'run_id', v_chat.${ch.activeRun});
    end if;
    update ${t.runs} x set ${r.status} = ${ctx.cast("runs", "status", "'cancelled'")}, ${r.endedAt} = now()
    where x.${r.id} = v_chat.${ch.activeRun} and x.${r.endedAt} is null;
  end if;
  insert into ${t.runs} (${runColumns})
  values (${runValues})
  returning ${r.id} into v_run_id;
  update ${t.chats} x set ${ch.activeStream} = claim_ai_chat_stream.stream, ${ch.activeRun} = v_run_id, ${ch.updatedAt} = now()
  where x.${ch.id} = v_chat.${ch.id};
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, null, 'stream.started', jsonb_build_object('streamId', claim_ai_chat_stream.stream, 'runId', v_run_id), false);
  return jsonb_build_object('claimed', true, 'stream_id', claim_ai_chat_stream.stream, 'run_id', v_run_id);
end;
$$;
${serviceGrant(`${fn("claim_ai_chat_stream")}(uuid, text, text, text, text, text)`)}

-- Ends the claim when the stream finished (the service role only) and
-- records the run's status, usage, gateway generation id and cost.
create or replace function ${fn("release_ai_chat_stream")}(chat uuid, stream text, status text default 'completed', usage jsonb default null, generation_id text default null, error text default null, cost_micro_usd bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_status text := coalesce(release_ai_chat_stream.status, 'completed');
  v_found boolean := false;${
    metering === ""
      ? ""
      : `
  v_run uuid;
  v_usage jsonb;
  v_owner uuid;
  v_tenant ${ctx.idType};`
  }
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  if v_status not in (${FINAL_RUN_STATES}) then
    ${raise("A run ends completed, failed or cancelled, not %", "22023", "AI_RUN_INVALID", "v_status")}
  end if;
  update ${t.runs} x set
    ${r.status} = ${ctx.cast("runs", "status", "v_status")},
    ${r.usage} = coalesce(release_ai_chat_stream.usage, x.${r.usage}),${assignments(
      ctx,
      "runs",
      [
        [
          "generation",
          () =>
            `coalesce(release_ai_chat_stream.generation_id, x.${r.generation})`,
        ],
        ["error", () => "release_ai_chat_stream.error"],
        [
          "cost",
          () => `coalesce(release_ai_chat_stream.cost_micro_usd, x.${r.cost})`,
        ],
      ],
    )}
    ${r.endedAt} = coalesce(x.${r.endedAt}, now())
  where x.${r.chat} = release_ai_chat_stream.chat and x.${r.stream} = release_ai_chat_stream.stream${
    metering === ""
      ? ";"
      : `
  returning x.${r.id}, x.${r.usage}, x.${r.owner} into v_run, v_usage, v_owner;${metering}`
  }
  update ${t.chats} x set ${ch.activeStream} = null, ${ch.activeRun} = null, ${ch.updatedAt} = now()
  where x.${ch.id} = release_ai_chat_stream.chat and x.${ch.activeStream} = release_ai_chat_stream.stream
  returning true into v_found;
  if coalesce(v_found, false) then
    perform ${fn("ai_chat_notify")}(release_ai_chat_stream.chat, null, 'stream.ended', jsonb_build_object('streamId', release_ai_chat_stream.stream, 'status', v_status), false);
  end if;
  return coalesce(v_found, false);
end;
$$;
${serviceGrant(`${fn("release_ai_chat_stream")}(uuid, text, text, jsonb, text, text, bigint)`)}

-- Asks the active reply to stop: the run turns cancel_requested and the
-- stream's cancel flag is set, which the writer reads on its next append.
-- Returns { stream_id, run_id }, or null when nothing is streaming.
create or replace function ${fn("request_ai_chat_stop")}(chat uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat ${t.chats};
begin${ownChat("request_ai_chat_stop")}
  if v_chat.${ch.activeStream} is null then
    return null;
  end if;
  update ${t.runs} x set ${r.status} = ${ctx.cast("runs", "status", "'cancel_requested'")}
  where x.${r.id} = v_chat.${ch.activeRun} and ${runStatus("x")} in ('queued', 'running');
  perform ${streams.fn("stream_cancel")}(v_chat.${ch.activeStream});
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, null, 'stream.stopping', jsonb_build_object('streamId', v_chat.${ch.activeStream}), false);
  return jsonb_build_object('stream_id', v_chat.${ch.activeStream}, 'run_id', v_chat.${ch.activeRun});
end;
$$;
${userGrant(`${fn("request_ai_chat_stop")}(uuid)`)}

-- Records the cost the gateway reported later for a generation id.
create or replace function ${fn("set_ai_run_cost")}(generation_id text, cost_micro_usd bigint, usage jsonb default null)
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
  update ${t.runs} x set${assignments(ctx, "runs", [["cost", () => "set_ai_run_cost.cost_micro_usd"]])}
    ${r.usage} = x.${r.usage} || coalesce(set_ai_run_cost.usage, '{}'::jsonb)
  where ${ctx.has("runs", "generation") ? `x.${r.generation} = set_ai_run_cost.generation_id` : "false"};
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${serviceGrant(`${fn("set_ai_run_cost")}(text, bigint, jsonb)`)}`;
}
