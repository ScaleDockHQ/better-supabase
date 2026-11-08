import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import {
  insertExtraColumns,
  raise,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  asText,
  rowJson,
  variableConflict,
  writtenPairs,
} from "./ai-chat-tables.ts";

export function participantJson(ctx: BlockSqlContext, row: string): string {
  return rowJson(ctx, "participants", row, [
    ["id", "id"],
    ["chat_id", "chat"],
    ["user_id", "user"],
    ["kind", "kind", "'user'"],
    ["team_id", "team"],
    ["customer_id", "customerUser"],
    ["email", "email"],
    ["role", "role"],
    ["added_by", "addedBy"],
    ["created_at", "createdAt"],
  ]);
}

/**
 * The people besides its owner who take part in a chat: a viewer reads it, an
 * editor also sends messages, stops a reply and switches branches. A chat with
 * participants is shared: adding one to a private chat makes it so.
 */
export function aiChatParticipants(
  ctx: BlockSqlContext,
  names: AiChatNames,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const pa = names.c.participants;
  const extras = names.extras.participants;
  const fields = "coalesce(add_ai_chat_participant.fields, '{}'::jsonb)";
  const inserted = insertExtraColumns(t.participants, extras, fields);

  const [columns, values] = writtenPairs(ctx, "participants", [
    ["chat", "v_chat.id"],
    ["user", "add_ai_chat_participant.participant"],
    ...(ctx.has("participants", "kind")
      ? ([["kind", ctx.cast("participants", "kind", "'user'")]] as const)
      : []),
    ["role", ctx.cast("participants", "role", "v_role")],
    ["addedBy", "auth.uid()"],
  ]);

  const share = ctx.scope.can("v_chat.tenant", perm.share);

  return `-- Adds someone to a chat, or changes their role: viewer or editor. The
-- chat's owner${names.tenantless ? "" : ` with ${perm.share}`}, or the service role.${extras.length > 0 ? " fields sets the\n-- app's extra columns." : ""}
create or replace function ${fn("add_ai_chat_participant")}(chat uuid, participant uuid, participant_role text default 'viewer', fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "participants")}
declare
  v_chat record;
  v_role text := coalesce(add_ai_chat_participant.participant_role, 'viewer');
  v_row ${t.participants};
begin
  select x.${ch.id} as id, x.${ch.owner} as owner, x.${ch.tenant} as tenant into v_chat
  from ${t.chats} x where x.${ch.id} = add_ai_chat_participant.chat for update;
  if not found or not (${SERVICE_CALLER} or coalesce(v_chat.owner = (select auth.uid()), false)) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "add_ai_chat_participant.chat")}
  end if;
  if not ${SERVICE_CALLER} and ${names.tenantless ? "v_chat.tenant is not null and " : ""}not ${share} then
    ${raise("You may not share chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  if v_role not in ('viewer', 'editor') then
    ${raise("A participant is a viewer or an editor, not %", "22023", "AI_CHAT_INVALID", "v_role")}
  end if;
  if add_ai_chat_participant.participant is null or add_ai_chat_participant.participant = v_chat.owner then
    ${raise("The owner already takes part in chat %", "22023", "AI_CHAT_INVALID", "add_ai_chat_participant.chat")}
  end if;
  if v_chat.tenant is not null and not ${ctx.scope.canUser("add_ai_chat_participant.participant", "v_chat.tenant", perm.read)} then
    ${raise("% can't read chats in the chat's organization", "22023", "AI_CHAT_INVALID", "add_ai_chat_participant.participant")}
  end if;
  insert into ${t.participants} (${columns}${inserted.columns})
  values (${values}${inserted.values})
  on conflict (${pa.chat}, ${pa.user})${ctx.has("participants", "kind") ? ` where ${pa.kind} = 'user'` : ""} do update set ${pa.role} = excluded.${pa.role}
  returning * into v_row;${writeExtraColumns(t.participants, extras, fields, `x.${pa.chat} = v_row.${pa.chat} and x.${pa.user} = v_row.${pa.user}`, "v_row")}
  ${markShared(ctx, names, "v_chat.id")}
  perform ${fn("ai_chat_notify")}(v_chat.id, add_ai_chat_participant.participant, 'participant.added', jsonb_build_object('userId', add_ai_chat_participant.participant, 'role', v_role), true);
  return ${participantJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("add_ai_chat_participant")}(uuid, uuid, text, jsonb)`)}

-- Removes someone from a chat: the chat's owner, the service role, or the
-- participant leaving. Returns whether they took part.
create or replace function ${fn("remove_ai_chat_participant")}(chat uuid, participant uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
${variableConflict(ctx, "participants")}
declare
  v_owner uuid;
  v_count integer;
begin
  select x.${ch.owner} into v_owner from ${t.chats} x where x.${ch.id} = remove_ai_chat_participant.chat;
  if not found or not (
    ${SERVICE_CALLER}
    or coalesce(v_owner = (select auth.uid()), false)
    or coalesce(remove_ai_chat_participant.participant = (select auth.uid()), false)
  ) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "remove_ai_chat_participant.chat")}
  end if;
  delete from ${t.participants} x
  where x.${pa.chat} = remove_ai_chat_participant.chat and x.${pa.user} = remove_ai_chat_participant.participant${ctx.has("participants", "kind") ? ` and x.${pa.kind}::text = 'user'` : ""};
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform ${fn("ai_chat_notify")}(remove_ai_chat_participant.chat, remove_ai_chat_participant.participant, 'participant.removed', jsonb_build_object('userId', remove_ai_chat_participant.participant), true);
  end if;
  return v_count > 0;
end;
$$;
${userGrant(`${fn("remove_ai_chat_participant")}(uuid, uuid)`)}

-- The people who take part in a chat, for anyone who reads it: the owner
-- first (role owner), then the rest oldest first.
create or replace function ${fn("list_ai_chat_participants")}(chat uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${fn("ai_chat_can_read")}(list_ai_chat_participants.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "list_ai_chat_participants.chat")}
  end if;
  return (
    select jsonb_build_array(jsonb_build_object('id', null, 'chat_id', c.${ch.id}, 'user_id', c.${ch.owner}, 'kind', 'user', 'team_id', null, 'customer_id', null, 'email', null, 'role', 'owner', 'added_by', null, 'created_at', ${ctx.has("chats", "createdAt") ? `c.${ch.createdAt}` : "null"}))
      || coalesce((
        select jsonb_agg(${participantJson(ctx, "x")} order by ${ctx.has("participants", "createdAt") ? `x.${pa.createdAt}, ` : ""}${ctx.has("participants", "id") ? `x.${pa.id}` : `x.${pa.user}`})
        from ${t.participants} x
        where x.${pa.chat} = list_ai_chat_participants.chat
      ), '[]'::jsonb)
    from ${t.chats} c where c.${ch.id} = list_ai_chat_participants.chat
  );
end;
$$;
${userGrant(`${fn("list_ai_chat_participants")}(uuid)`)}`;
}

/**
 * The statement that moves a private chat to `shared`: whoever takes part in a
 * chat, or holds its link, makes it readable beyond its owner.
 */
export function markShared(
  ctx: BlockSqlContext,
  names: AiChatNames,
  chat: string,
): string {
  const ch = names.c.chats;

  return `update ${names.t.chats} c set ${ch.visibility} = ${ctx.cast("chats", "visibility", "'shared'")}, ${ch.updatedAt} = now()
  where c.${ch.id} = ${chat} and ${asText(ctx, "chats", `c.${ch.visibility}`)} = 'private';`;
}
