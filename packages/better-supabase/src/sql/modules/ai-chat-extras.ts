import type { ModuleContext } from "../context.ts";
import type { ModuleLayout } from "../registry.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { accessModel } from "./access-model.ts";
import { canIn, raise, serviceGrant, userGrant } from "./ai-chat-sql.ts";

/** `jsonb_build_object` of an approval row, with stable keys. */
export function approvalJson(names: AiChatNames, row: string): string {
  const a = names.c.approvals;
  return `jsonb_build_object('approval_id', ${row}.${a.id}, 'chat_id', ${row}.${a.chat}, 'run_id', ${row}.${a.run}, 'message_id', ${row}.${a.message}, 'tool', ${row}.${a.tool}, 'tool_call_id', ${row}.${a.toolCall}, 'input', ${row}.${a.input}, 'decision', ${row}.${a.decision}, 'reason', ${row}.${a.reason}, 'signature', ${row}.${a.signature}, 'decided_by', ${row}.${a.decidedBy}, 'decided_at', ${row}.${a.decidedAt}, 'created_at', ${row}.${a.createdAt})`;
}

function inputJson(names: AiChatNames, row: string): string {
  const i = names.c.inputs;
  return `jsonb_build_object('id', ${row}.${i.id}, 'chat_id', ${row}.${i.chat}, 'run_id', ${row}.${i.run}, 'tool_call_id', ${row}.${i.toolCall}, 'question', ${row}.${i.question}, 'schema', ${row}.${i.schema}, 'answer', ${row}.${i.answer}, 'answered_at', ${row}.${i.answeredAt}, 'created_at', ${row}.${i.createdAt})`;
}

function modelJson(names: AiChatNames, row: string): string {
  const mo = names.c.models;
  return `jsonb_build_object('model_id', ${row}.${mo.id}, 'provider', ${row}.${mo.provider}, 'name', ${row}.${mo.name}, 'pricing', ${row}.${mo.pricing}, 'capabilities', ${row}.${mo.capabilities}, 'plans', to_jsonb(${row}.${mo.plans}), 'enabled', ${row}.${mo.enabled}, 'refreshed_at', ${row}.${mo.refreshedAt})`;
}

function moderationJson(names: AiChatNames, row: string): string {
  const md = names.c.moderation;
  return `jsonb_build_object('id', ${row}.${md.id}, 'organization_id', ${row}.${md.tenant}, 'chat_id', ${row}.${md.chat}, 'message_id', ${row}.${md.message}, 'user_id', ${row}.${md.user}, 'stage', ${row}.${md.stage}, 'category', ${row}.${md.category}, 'score', ${row}.${md.score}, 'action', ${row}.${md.action}, 'created_at', ${row}.${md.createdAt})`;
}

/** The provider's `canApprove` and `approvals`, when the `provider` access model decides. */
function approvalProvider(
  ctx: ModuleContext,
  layout: ModuleLayout,
):
  | {
      readonly scope: string;
      readonly canApprove: string;
      readonly distinct: boolean;
    }
  | undefined {
  const provider = layout.accessProvider;
  const canApprove = provider?.functions.canApprove;
  if (canApprove === undefined || accessModel(ctx) !== "provider")
    return undefined;
  return {
    scope: provider!.scope,
    canApprove,
    distinct: provider!.approvals?.distinctApprover === true,
  };
}

/**
 * Who may decide a waiting tool call besides the service role: a user the
 * provider's `canApprove` allows (never the requester with
 * `approvals.distinctApprover`), else the chat's owner.
 */
function approver(
  names: AiChatNames,
  provider: ReturnType<typeof approvalProvider>,
): string {
  const a = names.c.approvals;
  const ch = names.c.chats;
  if (provider === undefined) return `v_row.${a.owner} = (select auth.uid())`;
  const check = fillTemplate(
    "authorization.functions.canApprove",
    provider.canApprove,
    {
      scope: provider.scope,
      tenant: `(select c.${ch.tenant} from ${names.t.chats} c where c.${ch.id} = v_row.${a.chat})`,
      tool: `v_row.${a.tool}`,
    },
  );
  const distinct = provider.distinct
    ? `v_row.${a.owner} is distinct from (select auth.uid()) and `
    : "";
  return `(select auth.uid()) is not null and ${distinct}coalesce((${check}), false)`;
}

function approvals(
  ctx: ModuleContext,
  names: AiChatNames,
  layout: ModuleLayout,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const a = names.c.approvals;
  const po = names.c.policies;
  const i = names.c.inputs;
  const can = canIn;
  const provider = approvalProvider(ctx, layout);
  const serviceOnly = raise(
    "Only the server records this",
    "42501",
    "AI_CHAT_FORBIDDEN",
  );

  return `-- Records a tool call that waits for approval (the service role only).
-- approval holds approval_id, tool, tool_call_id and optionally input,
-- run_id, message_id and signature. A retry returns the stored row.
create or replace function ${fn("record_ai_tool_approval")}(chat uuid, approval jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_chat ${t.chats};
  v_row ${t.approvals};
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  select * into v_chat from ${t.chats} x where x.${ch.id} = record_ai_tool_approval.chat;
  if not found then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "record_ai_tool_approval.chat")}
  end if;
  insert into ${t.approvals} (${a.id}, ${a.chat}, ${a.owner}, ${a.run}, ${a.message}, ${a.tool}, ${a.toolCall}, ${a.input}, ${a.signature})
  values (
    record_ai_tool_approval.approval ->> 'approval_id', v_chat.${ch.id}, v_chat.${ch.owner},
    (record_ai_tool_approval.approval ->> 'run_id')::uuid, record_ai_tool_approval.approval ->> 'message_id',
    record_ai_tool_approval.approval ->> 'tool', record_ai_tool_approval.approval ->> 'tool_call_id',
    record_ai_tool_approval.approval -> 'input', record_ai_tool_approval.approval ->> 'signature'
  )
  on conflict (${a.id}) do nothing;
  select * into v_row from ${t.approvals} x where x.${a.id} = record_ai_tool_approval.approval ->> 'approval_id';
  if v_row.${a.chat} <> v_chat.${ch.id} then
    ${raise("Approval % belongs to another chat", "23505", "AI_APPROVAL_EXISTS", `v_row.${a.id}`)}
  end if;
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, null, 'approval.requested', jsonb_build_object('approvalId', v_row.${a.id}), false);
  return ${approvalJson(names, "v_row")};
end;
$$;
${serviceGrant(`${fn("record_ai_tool_approval")}(uuid, jsonb)`)}

-- Approves or denies a waiting tool call, once; the service role or ${provider === undefined ? "the chat's owner" : `a user the authorization provider's canApprove allows${provider.distinct ? " other than the chat's owner" : ""}`}.
-- Repeating the same decision returns the row.
create or replace function ${fn("decide_ai_tool_approval")}(approval_id text, approved boolean, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t.approvals};
  v_decision text := case when decide_ai_tool_approval.approved then 'approved' else 'denied' end;
begin
  select * into v_row from ${t.approvals} x where x.${a.id} = decide_ai_tool_approval.approval_id for update;
  if not found or not (${SERVICE_CALLER} or ${approver(names, provider)}) then
    ${raise("No approval %", "P0002", "AI_APPROVAL_NOT_FOUND", "decide_ai_tool_approval.approval_id")}
  end if;
  if decide_ai_tool_approval.approved is null then
    ${raise("Approve or deny", "22023", "AI_APPROVAL_INVALID")}
  end if;
  if v_row.${a.decision} is not null then
    if v_row.${a.decision} = v_decision then
      return ${approvalJson(names, "v_row")};
    end if;
    ${raise("Approval % was already %", "P0001", "AI_APPROVAL_DECIDED", `v_row.${a.id}`, `v_row.${a.decision}`)}
  end if;
  update ${t.approvals} x set
    ${a.decision} = v_decision,
    ${a.reason} = decide_ai_tool_approval.reason,
    ${a.decidedBy} = auth.uid(),
    ${a.decidedAt} = now()
  where x.${a.id} = v_row.${a.id}
  returning * into v_row;
  perform ${fn("ai_chat_notify")}(v_row.${a.chat}, null, 'approval.decided', jsonb_build_object('approvalId', v_row.${a.id}, 'decision', v_decision), false);
  return ${approvalJson(names, "v_row")};
end;
$$;
${userGrant(`${fn("decide_ai_tool_approval")}(text, boolean, text)`)}

-- A chat's approvals, oldest first; ids narrows them.
create or replace function ${fn("get_ai_tool_approvals")}(chat uuid, ids text[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${fn("ai_chat_can_read")}(get_ai_tool_approvals.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "get_ai_tool_approvals.chat")}
  end if;
  return (
    select coalesce(jsonb_agg(${approvalJson(names, "x")} order by x.${a.createdAt}), '[]'::jsonb)
    from ${t.approvals} x
    where x.${a.chat} = get_ai_tool_approvals.chat
      and (get_ai_tool_approvals.ids is null or x.${a.id} = any (get_ai_tool_approvals.ids))
  );
end;
$$;
${userGrant(`${fn("get_ai_tool_approvals")}(uuid, text[])`)}

-- Sets whether a tool runs (auto), asks (ask) or never runs (deny) in a
-- tenant (${perm.admin}); policy null removes the rule.
create or replace function ${fn("set_ai_tool_policy")}(tenant ${ctx.idType}, tool text, policy text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${can("set_ai_tool_policy.tenant", perm.admin)}) then
    ${raise("You may not change tool policies here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  if set_ai_tool_policy.policy is null then
    delete from ${t.policies} x where x.${po.tenant} = set_ai_tool_policy.tenant and x.${po.tool} = set_ai_tool_policy.tool;
    return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', null);
  end if;
  insert into ${t.policies} (${po.tenant}, ${po.tool}, ${po.policy})
  values (set_ai_tool_policy.tenant, set_ai_tool_policy.tool, set_ai_tool_policy.policy)
  on conflict (${po.tenant}, ${po.tool}) do update set ${po.policy} = excluded.${po.policy}, ${po.updatedAt} = now();
  return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy);
end;
$$;
${userGrant(`${fn("set_ai_tool_policy")}(${ctx.idType}, text, text)`)}

-- A tenant's tool rules as { tool: policy }, for members (${perm.read}).
create or replace function ${fn("ai_tool_policies_for")}(tenant ${ctx.idType})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER} or ${can("ai_tool_policies_for.tenant", perm.read)}) then
    return '{}'::jsonb;
  end if;
  return (
    select coalesce(jsonb_object_agg(x.${po.tool}, x.${po.policy}), '{}'::jsonb)
    from ${t.policies} x where x.${po.tenant} = ai_tool_policies_for.tenant
  );
end;
$$;
${userGrant(`${fn("ai_tool_policies_for")}(${ctx.idType})`)}

-- Records a question for the user (the service role only): input holds
-- question and optionally schema (a JSON Schema), run_id and tool_call_id.
create or replace function ${fn("open_ai_pending_input")}(chat uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat ${t.chats};
  v_row ${t.inputs};
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  select * into v_chat from ${t.chats} x where x.${ch.id} = open_ai_pending_input.chat;
  if not found then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "open_ai_pending_input.chat")}
  end if;
  insert into ${t.inputs} (${i.chat}, ${i.owner}, ${i.run}, ${i.toolCall}, ${i.question}, ${i.schema})
  values (
    v_chat.${ch.id}, v_chat.${ch.owner}, (open_ai_pending_input.input ->> 'run_id')::uuid,
    open_ai_pending_input.input ->> 'tool_call_id', open_ai_pending_input.input ->> 'question',
    open_ai_pending_input.input -> 'schema'
  )
  returning * into v_row;
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, null, 'input.requested', jsonb_build_object('inputId', v_row.${i.id}), false);
  return ${inputJson(names, "v_row")};
end;
$$;
${serviceGrant(`${fn("open_ai_pending_input")}(uuid, jsonb)`)}

-- Answers a question once; the chat's owner or the service role.
create or replace function ${fn("answer_ai_pending_input")}(id uuid, answer jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t.inputs};
begin
  select * into v_row from ${t.inputs} x where x.${i.id} = answer_ai_pending_input.id for update;
  if not found or not (${SERVICE_CALLER} or v_row.${i.owner} = (select auth.uid())) then
    ${raise("No question %", "P0002", "AI_INPUT_NOT_FOUND", "answer_ai_pending_input.id")}
  end if;
  if v_row.${i.answeredAt} is not null then
    ${raise("Question % was answered", "P0001", "AI_INPUT_ANSWERED", "answer_ai_pending_input.id")}
  end if;
  update ${t.inputs} x set ${i.answer} = coalesce(answer_ai_pending_input.answer, 'null'::jsonb), ${i.answeredAt} = now()
  where x.${i.id} = v_row.${i.id}
  returning * into v_row;
  perform ${fn("ai_chat_notify")}(v_row.${i.chat}, null, 'input.answered', jsonb_build_object('inputId', v_row.${i.id}), false);
  return ${inputJson(names, "v_row")};
end;
$$;
${userGrant(`${fn("answer_ai_pending_input")}(uuid, jsonb)`)}`;
}

function sharing(ctx: ModuleContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const m = names.c.messages;
  const f = names.c.feedback;
  const sh = names.c.shares;
  const can = canIn;
  const shared = ctx.emit({
    type: "ai_chat.shared",
    payload: `jsonb_build_object('chatId', v_chat.${ch.id}, 'shareId', v_id, 'organizationId', v_chat.${ch.tenant}::text, 'ownerId', v_chat.${ch.owner}, 'leafId', v_leaf)`,
    subject: `'ai-chats/' || v_chat.${ch.id}::text`,
    tenant: `v_chat.${ch.tenant}`,
    key: `'ai_chat.shared:' || v_id::text`,
  });
  const hash = (token: string): string =>
    `encode(sha256(convert_to(${token}, 'UTF8')), 'hex')`;

  return `-- Rates a reply: 1 or -1, with an optional reason and comment; rating null
-- removes the caller's rating. Anyone who can read the chat may rate.
create or replace function ${fn("rate_ai_message")}(chat uuid, message_id text, rating integer, reason text default null, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not ${fn("ai_chat_can_read")}(rate_ai_message.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "rate_ai_message.chat")}
  end if;
  if not exists (select 1 from ${t.messages} x where x.${m.chat} = rate_ai_message.chat and x.${m.id} = rate_ai_message.message_id) then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "rate_ai_message.message_id")}
  end if;
  if rate_ai_message.rating is null then
    delete from ${t.feedback} x
    where x.${f.chat} = rate_ai_message.chat and x.${f.message} = rate_ai_message.message_id and x.${f.user} = auth.uid();
    return null;
  end if;
  insert into ${t.feedback} (${f.chat}, ${f.message}, ${f.user}, ${f.rating}, ${f.reason}, ${f.comment})
  values (rate_ai_message.chat, rate_ai_message.message_id, auth.uid(), rate_ai_message.rating, rate_ai_message.reason, rate_ai_message.comment)
  on conflict (${f.chat}, ${f.message}, ${f.user}) do update set
    ${f.rating} = excluded.${f.rating}, ${f.reason} = excluded.${f.reason}, ${f.comment} = excluded.${f.comment}, ${f.updatedAt} = now();
  return jsonb_build_object('chat_id', rate_ai_message.chat, 'message_id', rate_ai_message.message_id, 'rating', rate_ai_message.rating, 'reason', rate_ai_message.reason, 'comment', rate_ai_message.comment);
end;
$$;
${userGrant(`${fn("rate_ai_message")}(uuid, text, integer, text, text)`)}

-- Creates a read-only link to the branch ending at leaf (default: the one
-- the chat shows); the owner with ${perm.share}. The token is returned once
-- and only its SHA-256 is stored.
create or replace function ${fn("share_ai_chat")}(chat uuid, leaf text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat ${t.chats};
  v_leaf text;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_id uuid;
  v_created timestamptz;
begin
  select * into v_chat from ${t.chats} x where x.${ch.id} = share_ai_chat.chat;
  if not found or v_chat.${ch.owner} is distinct from auth.uid() then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "share_ai_chat.chat")}
  end if;
  if not ${can(`v_chat.${ch.tenant}`, perm.share)} then
    ${raise("You may not share chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_chat.${ch.leaf});
  if v_leaf is null or not exists (select 1 from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_leaf) then
    ${raise("Nothing to share yet", "P0002", "AI_MESSAGE_NOT_FOUND")}
  end if;
  insert into ${t.shares} (${sh.chat}, ${sh.tokenHash}, ${sh.leaf}, ${sh.createdBy})
  values (v_chat.${ch.id}, ${hash("v_token")}, v_leaf, auth.uid())
  returning ${sh.id}, ${sh.createdAt} into v_id, v_created;
  ${shared}
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf, 'created_at', v_created);
end;
$$;
${userGrant(`${fn("share_ai_chat")}(uuid, text)`)}

-- Revokes a link; whoever made it, the chat's owner or the service role.
create or replace function ${fn("revoke_ai_chat_share")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update ${t.shares} x set ${sh.revokedAt} = now()
  where x.${sh.id} = revoke_ai_chat_share.id
    and x.${sh.revokedAt} is null
    and (
      ${SERVICE_CALLER}
      or x.${sh.createdBy} = (select auth.uid())
      or exists (select 1 from ${t.chats} c where c.${ch.id} = x.${sh.chat} and c.${ch.owner} = (select auth.uid()))
    );
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${userGrant(`${fn("revoke_ai_chat_share")}(uuid)`)}

-- A chat's links, newest first, without their tokens.
create or replace function ${fn("list_ai_chat_shares")}(chat uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.${sh.id}, 'leaf_id', x.${sh.leaf}, 'created_by', x.${sh.createdBy},
    'created_at', x.${sh.createdAt}, 'revoked_at', x.${sh.revokedAt}
  ) order by x.${sh.createdAt} desc), '[]'::jsonb)
  from ${t.shares} x
  join ${t.chats} c on c.${ch.id} = x.${sh.chat}
  where x.${sh.chat} = list_ai_chat_shares.chat
    and (${SERVICE_CALLER} or c.${ch.owner} = (select auth.uid()));
$$;
${userGrant(`${fn("list_ai_chat_shares")}(uuid)`)}

-- The shared branch for a link token, for anyone holding it: { chat,
-- leaf_id, messages }, or null when the link is unknown or revoked.
create or replace function ${fn("get_shared_ai_chat")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_share ${t.shares};
  v_chat ${t.chats};
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into v_share from ${t.shares} x
  where x.${sh.tokenHash} = ${hash("get_shared_ai_chat.token")} and x.${sh.revokedAt} is null;
  if not found then
    return null;
  end if;
  select * into v_chat from ${t.chats} x where x.${ch.id} = v_share.${sh.chat};
  return jsonb_build_object(
    'chat', jsonb_build_object('id', v_chat.${ch.id}, 'title', v_chat.${ch.title}, 'model', v_chat.${ch.model}, 'created_at', v_chat.${ch.createdAt}),
    'leaf_id', v_share.${sh.leaf},
    'messages', ${fn("ai_message_path_of")}(v_chat.${ch.id}, v_share.${sh.leaf}, false)
  );
end;
$$;
revoke execute on function ${fn("get_shared_ai_chat")}(text) from public;
grant execute on function ${fn("get_shared_ai_chat")}(text) to anon, authenticated, service_role;`;
}

function catalog(ctx: ModuleContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const mo = names.c.models;
  const md = names.c.moderation;
  const can = canIn;
  const planned = ctx.installed("entitlements")
    ? `(v_tenant is not null and x.${mo.plans} && better_supabase.tenant_entitlements(v_tenant))`
    : "false";
  const serviceOnly = raise(
    "Only the server records this",
    "42501",
    "AI_CHAT_FORBIDDEN",
  );

  return `-- Upserts models from the gateway (the service role only): models is an
-- array, or an object whose models key holds one. Each element holds id, and optionally provider, name, pricing, capabilities, plans and
-- enabled. prune deletes the models missing from the list.
create or replace function ${fn("upsert_ai_models")}(models jsonb, prune boolean default false)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_models jsonb := case jsonb_typeof(upsert_ai_models.models)
    when 'array' then upsert_ai_models.models
    when 'object' then coalesce(upsert_ai_models.models -> 'models', '[]'::jsonb)
    else '[]'::jsonb
  end;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  insert into ${t.models} (${mo.id}, ${mo.provider}, ${mo.name}, ${mo.pricing}, ${mo.capabilities}, ${mo.plans}, ${mo.enabled})
  select
    e ->> 'id',
    coalesce(e ->> 'provider', split_part(e ->> 'id', '/', 1)),
    coalesce(e ->> 'name', e ->> 'id'),
    coalesce(e -> 'pricing', '{}'::jsonb),
    coalesce(e -> 'capabilities', '{}'::jsonb),
    coalesce(array(select jsonb_array_elements_text(e -> 'plans')), '{}'::text[]),
    coalesce((e ->> 'enabled')::boolean, true)
  from jsonb_array_elements(v_models) e
  where nullif(e ->> 'id', '') is not null
  on conflict (${mo.id}) do update set
    ${mo.provider} = excluded.${mo.provider},
    ${mo.name} = excluded.${mo.name},
    ${mo.pricing} = excluded.${mo.pricing},
    ${mo.capabilities} = excluded.${mo.capabilities},
    ${mo.refreshedAt} = now();
  get diagnostics v_count = row_count;
  if upsert_ai_models.prune then
    delete from ${t.models} x
    where x.${mo.id} not in (select e ->> 'id' from jsonb_array_elements(v_models) e where e ->> 'id' is not null);
  end if;
  return v_count;
end;
$$;
${serviceGrant(`${fn("upsert_ai_models")}(jsonb, boolean)`)}

-- The models a tenant may pick: enabled ones with no plans, and, with the
-- entitlements module, those whose plans the tenant holds.
create or replace function ${fn("allowed_ai_models")}(tenant ${ctx.idType} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := allowed_ai_models.tenant;
begin
  if v_tenant is not null and not (${SERVICE_CALLER} or ${can("v_tenant", perm.read)}) then
    v_tenant := null;
  end if;
  return (
    select coalesce(jsonb_agg(${modelJson(names, "x")} order by x.${mo.provider}, x.${mo.name}), '[]'::jsonb)
    from ${t.models} x
    where x.${mo.enabled} and (cardinality(x.${mo.plans}) = 0 or ${planned})
  );
end;
$$;
${userGrant(`${fn("allowed_ai_models")}(${ctx.idType})`)}

-- Records a moderation decision (the service role only): event holds
-- organization_id, stage, category, action and optionally chat_id,
-- message_id, user_id and score.
create or replace function ${fn("record_ai_moderation_event")}(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t.moderation};
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  insert into ${t.moderation} (${md.tenant}, ${md.chat}, ${md.message}, ${md.user}, ${md.stage}, ${md.category}, ${md.score}, ${md.action})
  values (
    (record_ai_moderation_event.event ->> 'organization_id')::${ctx.idType},
    (record_ai_moderation_event.event ->> 'chat_id')::uuid,
    record_ai_moderation_event.event ->> 'message_id',
    (record_ai_moderation_event.event ->> 'user_id')::uuid,
    record_ai_moderation_event.event ->> 'stage',
    record_ai_moderation_event.event ->> 'category',
    (record_ai_moderation_event.event ->> 'score')::real,
    record_ai_moderation_event.event ->> 'action'
  )
  returning * into v_row;
  return ${moderationJson(names, "v_row")};
end;
$$;
${serviceGrant(`${fn("record_ai_moderation_event")}(jsonb)`)}

-- A tenant's moderation decisions, newest first (${perm.moderate}).
create or replace function ${fn("list_ai_moderation_events")}(tenant ${ctx.idType}, size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER} or ${can("list_ai_moderation_events.tenant", perm.moderate)}) then
    ${raise("You may not review moderation here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  return (
    select coalesce(jsonb_agg(${moderationJson(names, "page")} order by page.${md.createdAt} desc), '[]'::jsonb)
    from (
      select * from ${t.moderation} x
      where x.${md.tenant} = list_ai_moderation_events.tenant
      order by x.${md.createdAt} desc
      limit least(greatest(coalesce(list_ai_moderation_events.size, 100), 1), 1000)
    ) page
  );
end;
$$;
${userGrant(`${fn("list_ai_moderation_events")}(${ctx.idType}, integer)`)}

-- Deletes expired temporary chats, at most batch per call.
create or replace function ${fn("purge_ai_chats")}(batch integer default 1000)
returns integer
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
  with doomed as (
    select x.${ch.id} from ${t.chats} x
    where x.${ch.temporary} and x.${ch.expiresAt} <= now()
    limit greatest(coalesce(purge_ai_chats.batch, 1000), 1)
  )
  delete from ${t.chats} c using doomed where c.${ch.id} = doomed.${ch.id};
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_ai_chats")}(integer)`)}`;
}

/** Approvals, policies, questions, feedback, links, models and moderation. */
export function aiChatExtras(
  ctx: ModuleContext,
  names: AiChatNames,
  layout: ModuleLayout,
): string {
  return `${approvals(ctx, names, layout)}

${sharing(ctx, names)}

${catalog(ctx, names)}`;
}
