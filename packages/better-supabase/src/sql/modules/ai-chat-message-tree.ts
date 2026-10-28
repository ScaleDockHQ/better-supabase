import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { raise, userGrant, writeExtraColumns } from "../shared.ts";

/** What the message functions share with `aiChatMessages`. */
export interface MessageTreeParts {
  /** `jsonb_build_object` of message `row`; `parent` is its `parent_id`. */
  readonly json: (row: string, native: string, parent: string) => string;
  /** Locks the chat into `v_chat`, for its owner, an editor or the service role. */
  readonly ownChat: (name: string) => string;
  /** `row.role` as text. */
  readonly role: (row: string) => string;
  /** The columns and values of a new user message. */
  readonly user: readonly [string, string];
}

/**
 * `ai_message_key`, which turns a text id into a uuid and rejects one that
 * isn't, when `options.messages.key` is `uuid`. Empty otherwise.
 */
export function messageKey(ctx: BlockSqlContext, names: AiChatNames): string {
  if (!names.messages.uuid) {
    return "";
  }

  const fn = ctx.fn("ai_message_key");

  return `-- A message id: a uuid, or AI_MESSAGE_INVALID.
create or replace function ${fn}(value text)
returns uuid
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if value !~* '^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$' then
    ${raise("% is not a message id; ids are uuids", "22023", "AI_MESSAGE_INVALID", "value")}
  end if;
  return value::uuid;
end;
$$;
revoke execute on function ${fn}(text) from public, anon, authenticated;

`;
}

/**
 * The read and branch functions over the messages: a tree with siblings, or one
 * list per chat with `options.messages.tree: false`.
 */
export function messagePaths(
  ctx: BlockSqlContext,
  names: AiChatNames,
  parts: MessageTreeParts,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const m = names.c.messages;
  const key = names.messages.id;
  const tree = names.messages.tree;

  const pathOf = tree
    ? `  with recursive up as (
    select x.*, 0 as depth from ${t.messages} x
    where x.${m.chat} = ai_message_path_of.chat and x.${m.id} = ${key("ai_message_path_of.leaf")}
    union all
    select x.*, up.depth + 1 from ${t.messages} x
    join up on x.${m.chat} = up.${m.chat} and x.${m.id} = up.${m.parent}
    where up.depth < 10000
  )
  select coalesce(jsonb_agg(
    ${parts.json("up", "ai_message_path_of.include_native", `up.${m.parent}`)} || jsonb_build_object(
      'sibling_count', (select count(*) from ${t.messages} sb where sb.${m.chat} = up.${m.chat} and sb.${m.parent} is not distinct from up.${m.parent}),
      'sibling_index', (select count(*) from ${t.messages} sb where sb.${m.chat} = up.${m.chat} and sb.${m.parent} is not distinct from up.${m.parent} and sb.${m.seq} < up.${m.seq})
    )
    order by up.depth desc
  ), '[]'::jsonb)
  from up;`
    : `  select coalesce(jsonb_agg(
    ${parts.json("up", "ai_message_path_of.include_native", "up.prev")} || jsonb_build_object('sibling_count', 1, 'sibling_index', 0)
    order by up.${m.seq}
  ), '[]'::jsonb)
  from (
    select x.*, lag(x.${m.id}) over (order by x.${m.seq}) as prev from ${t.messages} x
    where x.${m.chat} = ai_message_path_of.chat
      and x.${m.seq} <= (select l.${m.seq} from ${t.messages} l where l.${m.chat} = ai_message_path_of.chat and l.${m.id} = ${key("ai_message_path_of.leaf")})
  ) up;`;

  const siblings = tree
    ? `  select x.${m.parent} into v_parent from ${t.messages} x
  where x.${m.chat} = ai_message_siblings.chat and x.${m.id} = ${key("ai_message_siblings.message_id")};
  if not found then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "ai_message_siblings.message_id")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x.${m.id}, 'role', x.${m.role}, 'created_at', x.${m.createdAt}) order by x.${m.seq}), '[]'::jsonb)
    from ${t.messages} x
    where x.${m.chat} = ai_message_siblings.chat and x.${m.parent} is not distinct from v_parent
  );`
    : `  return (
    select jsonb_build_array(jsonb_build_object('id', x.${m.id}, 'role', x.${m.role}, 'created_at', x.${m.createdAt}))
    from ${t.messages} x
    where x.${m.chat} = ai_message_siblings.chat and x.${m.id} = ${key("ai_message_siblings.message_id")}
  );`;

  const linearSiblings = tree
    ? ""
    : `
  if not exists (select 1 from ${t.messages} x where x.${m.chat} = ai_message_siblings.chat and x.${m.id} = ${key("ai_message_siblings.message_id")}) then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "ai_message_siblings.message_id")}
  end if;`;

  const switchBody = tree
    ? `  if not exists (select 1 from ${t.messages} x where x.${m.chat} = switch_ai_branch.chat and x.${m.id} = ${key("switch_ai_branch.message_id")}) then
    ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "switch_ai_branch.message_id")}
  end if;
  with recursive down as (
    select ${key("switch_ai_branch.message_id")} as id, 0 as depth
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
  return jsonb_build_object('leaf_id', v_leaf);`
    : `  ${raise("Chat % keeps one list of messages, without branches", "22023", "AI_CHAT_LINEAR", "switch_ai_branch.chat")}`;

  return `-- The ${tree ? "branch" : "messages"} that ${tree ? "ends" : "end"} at leaf, ${tree ? "root" : "oldest"} first, with each message's place among
-- its siblings (sibling_index of sibling_count) for the "2 / 3" arrows. No
-- permission check: callers check first.
create or replace function ${fn("ai_message_path_of")}(chat uuid, leaf text, include_native boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
${pathOf}
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
  select coalesce(ai_message_path.leaf, x.${ch.leaf}::text) into v_leaf from ${t.chats} x where x.${ch.id} = ai_message_path.chat;
  if v_leaf is null then
    return '[]'::jsonb;
  end if;
  return ${fn("ai_message_path_of")}(ai_message_path.chat, v_leaf, coalesce(ai_message_path.include_native, false));
end;
$$;
${userGrant(`${fn("ai_message_path")}(uuid, text, boolean)`)}

-- The versions of a message (same parent), oldest first${tree ? "" : ": a linear chat\n-- keeps one, the message itself"}.
create or replace function ${fn("ai_message_siblings")}(chat uuid, message_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$${
    tree
      ? `
declare
  v_parent ${names.messages.idType};`
      : ""
  }
begin
  if not ${fn("ai_chat_can_read")}(ai_message_siblings.chat) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "ai_message_siblings.chat")}
  end if;${linearSiblings}
${siblings}
end;
$$;
${userGrant(`${fn("ai_message_siblings")}(uuid, text)`)}

-- Shows the branch through message_id: the chat's leaf becomes the newest
-- descendant of message_id, following the latest child at each turn.${tree ? "" : "\n-- A linear chat has no branches, so it raises AI_CHAT_LINEAR."}
create or replace function ${fn("switch_ai_branch")}(chat uuid, message_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chat ${t.chats};
  v_leaf ${names.messages.idType};
begin${parts.ownChat("switch_ai_branch")}
${switchBody}
end;
$$;
${userGrant(`${fn("switch_ai_branch")}(uuid, text)`)}`;
}

/**
 * `append_ai_user_message`: a new message under the leaf, a new version of a
 * message, or a regenerate. A linear chat replaces the messages after the
 * edited or regenerated one instead of adding a sibling.
 */
export function appendUserMessage(
  ctx: BlockSqlContext,
  names: AiChatNames,
  parts: MessageTreeParts,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const m = names.c.messages;
  const mode = names.messages;
  const key = mode.id;
  const [userColumns, userValues] = parts.user;

  const fields =
    "coalesce(append_ai_user_message.message -> 'fields', '{}'::jsonb)";

  const extras = writeExtraColumns(
    t.messages,
    names.extras.messages,
    fields,
    `x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_id`,
  );

  const previous = (row: string): string =>
    `(select p.${m.id} from ${t.messages} p where p.${m.chat} = ${row}.${m.chat} and p.${m.seq} < ${row}.${m.seq} order by p.${m.seq} desc limit 1)`;

  const regenerate = mode.tree
    ? `    v_parent := case when ${parts.role("v_existing")} = 'user' then v_existing.${m.id} else v_existing.${m.parent} end;`
    : `    v_parent := case when ${parts.role("v_existing")} = 'user' then v_existing.${m.id} else ${previous("v_existing")} end;
    delete from ${t.messages} x
    where x.${m.chat} = v_chat.${ch.id}
      and x.${m.seq} > coalesce((select p.${m.seq} from ${t.messages} p where p.${m.chat} = v_chat.${ch.id} and p.${m.id} = v_parent), 0);`;

  const edit = mode.tree
    ? `    v_parent := v_existing.${m.parent};
    v_id := gen_random_uuid()${mode.uuid ? "" : "::text"};`
    : `    v_parent := ${previous("v_existing")};
    update ${t.messages} x set ${m.parts} = append_ai_user_message.message -> 'parts'${ctx.has("messages", "metadata") ? `, ${m.metadata} = case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else x.${m.metadata} end` : ""}${ctx.has("messages", "author") ? `, ${m.author} = (select auth.uid())` : ""}
    where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_id;${extras}
    delete from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.seq} > v_existing.${m.seq};
    update ${t.chats} x set ${ch.leaf} = v_id, ${ch.lastMessageAt} = clock_timestamp(), ${ch.updatedAt} = now() where x.${ch.id} = v_chat.${ch.id};
    perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, v_chat.${ch.owner}, 'message.saved', jsonb_build_object('messageId', v_id), not v_chat.${ch.temporary});
    return jsonb_build_object('message_id', v_id, 'parent_id', v_parent, 'created', true);`;

  const version = mode.tree
    ? `    select x.${m.parent} into v_parent from ${t.messages} x
    where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = ${key("append_ai_user_message.message_id")};
    if not found then
      ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "append_ai_user_message.message_id")}
    end if;`
    : `    select * into v_existing from ${t.messages} x
    where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = ${key("append_ai_user_message.message_id")};
    if not found then
      ${raise("No message %", "P0002", "AI_MESSAGE_NOT_FOUND", "append_ai_user_message.message_id")}
    end if;
    v_parent := ${previous("v_existing")};
    delete from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.seq} >= v_existing.${m.seq};`;

  const sameParent = mode.tree
    ? `v_existing.${m.parent}`
    : previous("v_existing");

  return `-- Stores the user's message. trigger 'submit-message' appends message under
-- the chat's leaf, or, with message_id, as a new version of that message.
-- The id is the client's, so a retry with the same parts is a no-op; the
-- same id with other parts is an edit and ${mode.tree ? "gets a fresh id" : "replaces the message and\n-- the ones after it"}. trigger
-- 'regenerate-message' stores nothing and moves the leaf to the user
-- message whose reply is regenerated${mode.tree ? "" : ", deleting the messages after it"}. Returns { message_id, parent_id,
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
  v_id ${mode.idType};
  v_parent ${mode.idType};
  v_target ${mode.idType};
begin${parts.ownChat("append_ai_user_message")}
  if coalesce(append_ai_user_message.trigger, 'submit-message') = 'regenerate-message' then
    v_target := coalesce(${key("append_ai_user_message.message_id")}, v_chat.${ch.leaf});
    select * into v_existing from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_target;
    if not found then
      ${raise("No message % to regenerate", "P0002", "AI_MESSAGE_NOT_FOUND", "v_target")}
    end if;
${regenerate}
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
  v_id := ${key("append_ai_user_message.message ->> 'id'")};
  select * into v_existing from ${t.messages} x where x.${m.chat} = v_chat.${ch.id} and x.${m.id} = v_id;
  if found then
    if v_existing.${m.parts} = append_ai_user_message.message -> 'parts' then
      return jsonb_build_object('message_id', v_id, 'parent_id', ${sameParent}, 'created', false);
    end if;
${edit}
  elsif append_ai_user_message.message_id is not null then
${version}
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
${userGrant(`${fn("append_ai_user_message")}(uuid, jsonb, text, text)`)}`;
}
