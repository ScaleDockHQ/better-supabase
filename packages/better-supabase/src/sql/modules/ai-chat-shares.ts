import type { BlockSqlContext } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";

import { fail, sha256Hex, userGrant } from "../shared.ts";
import { AI_TOOL_SUBJECT } from "./ai-chat-extras.ts";
import { liveShareLink } from "./share-links.ts";

/**
 * Ai-chat sharing on the share-links block in `ctx`: the old functions stay
 * callable and write share links instead of ai_chat_shares.
 */
function aiChatShareSql(ctx: BlockSqlContext): string {
  const links = ctx.table("links");

  return `
-- ai-chat sharing is this block. The old functions stay callable and write
-- share_links instead of ai_chat_shares.
do $$
begin
  if to_regclass('${ctx.schema}.ai_chat_shares') is not null then
    insert into ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}, ${ctx.col("links", "tokenHash")}, ${ctx.col("links", "createdBy")}${ctx.has("links", "leaf") ? `, ${ctx.col("links", "leaf")}` : ""})
    select c.${ctx.naming.rename("organization_id")}, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by${ctx.has("links", "leaf") ? ", s.leaf_id" : ""}
    from ${ctx.schema}.ai_chat_shares s
    join ${ctx.schema}.ai_chats c on c.id = s.chat_id
    on conflict (${ctx.col("links", "tokenHash")}) do nothing;
  end if;
end;
$$;
create or replace function ${ctx.fn("share_ai_chat")}(chat uuid, leaf text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant ${ctx.idType};
  v_owner uuid;
  v_leaf text;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  select ${ctx.naming.rename("organization_id")}, owner_id, current_leaf_id into v_tenant, v_owner, v_leaf
  from ${ctx.schema}.ai_chats where id = share_ai_chat.chat;
  if not found or v_owner is distinct from auth.uid() then
    ${fail("AI_CHAT_NOT_FOUND", "no chat", "P0002")}
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_leaf);
  insert into ${links} (${ctx.col("links", "tenant")}, ${ctx.col("links", "subjectType")}, ${ctx.col("links", "subjectId")}, ${ctx.col("links", "tokenHash")}, ${ctx.col("links", "role")}, ${ctx.col("links", "createdBy")}${ctx.has("links", "leaf") ? `, ${ctx.col("links", "leaf")}` : ""})
  values (v_tenant, 'ai-chat', share_ai_chat.chat::text, ${sha256Hex("convert_to(v_token, 'utf8')")}, 'view', auth.uid()${ctx.has("links", "leaf") ? ", v_leaf" : ""})
  returning ${ctx.col("links", "id")} into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf);
end;
$$;
${userGrant(`${ctx.fn("share_ai_chat")}(uuid, text)`)}
create or replace function ${ctx.fn("revoke_ai_chat_share")}(id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  return ${ctx.fn("revoke_share_link")}(revoke_ai_chat_share.id);
end;
$$;
create or replace function ${ctx.fn("list_ai_chat_shares")}(chat uuid)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select ${ctx.fn("list_share_links")}('ai-chat', list_ai_chat_shares.chat::text)
$$;
create or replace function ${ctx.fn("get_shared_ai_chat")}(token text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_subject text;
  v_tenant text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l.${ctx.col("links", "subjectId")}, l.${ctx.col("links", "tenant")}::text, ${ctx.has("links", "leaf") ? `l.${ctx.col("links", "leaf")}` : "null"}
    into v_subject, v_tenant, v_leaf
  from ${links} l
  where ${liveShareLink(ctx, "l", "get_shared_ai_chat.token", "'ai-chat'")};
  if not found or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  -- The chat must still live in the tenant the link was created in.
  if not exists (select 1 from ${ctx.schema}.ai_chats where id = v_chat_id and ${ctx.naming.rename("organization_id")}::text = v_tenant) then
    return null;
  end if;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from ${ctx.schema}.ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', ${ctx.fn("ai_message_path_of")}(v_chat_id, v_leaf, false)
  );
end;
$$;
`;
}

/** What ai-chat adds to approvals and share-links. */
export const AI_CHAT_CONTRIBUTES: BlockContributes = {
  "share-links": (_own, target) => [
    {
      subject: "ai-chat",
      exists: ({ id, tenant }) =>
        `exists (select 1 from ${target.schema}.ai_chats s where s.id::text = ${id} and s.${target.naming.rename("organization_id")}::text = ${tenant}::text and s.owner_id = auth.uid())`,
      sql: aiChatShareSql(target),
    },
  ],
  approvals: (own) => [
    {
      subject: AI_TOOL_SUBJECT,
      access: "linked",
      approve: ({ subjectId, comment }) =>
        `perform ${own.fn("apply_ai_tool_approval")}(${subjectId}, true, ${comment});`,
      reject: ({ subjectId, comment }) =>
        `perform ${own.fn("apply_ai_tool_approval")}(${subjectId}, false, ${comment});`,
      approvable: ({ subjectId }) =>
        `${own.fn("ai_tool_approval_approvable")}(${subjectId})`,
    },
  ],
};
