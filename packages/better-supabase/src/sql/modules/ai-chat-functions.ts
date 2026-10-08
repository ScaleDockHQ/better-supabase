import type { ModuleContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { aiChatExtras } from "./ai-chat-extras.ts";
import { canIn, raise, serviceGrant, userGrant } from "./ai-chat-sql.ts";

/** `jsonb_build_object` of a chat row, with stable keys whatever the column names. */
function chatJson(names: AiChatNames, row: string): string {
  const ch = names.c.chats;
  const keys: readonly (readonly [string, string])[] = [
    ["id", ch.id],
    ["organization_id", ch.tenant],
    ["owner_id", ch.owner],
    ["project_id", ch.project],
    ["agent_id", ch.agent],
    ["title", ch.title],
    ["model", ch.model],
    ["visibility", ch.visibility],
    ["pinned", ch.pinned],
    ["archived_at", ch.archivedAt],
    ["is_temporary", ch.temporary],
    ["expires_at", ch.expiresAt],
    ["current_leaf_id", ch.leaf],
    ["active_stream_id", ch.activeStream],
    ["active_run_id", ch.activeRun],
    ["last_message_at", ch.lastMessageAt],
    ["created_at", ch.createdAt],
    ["updated_at", ch.updatedAt],
  ];
  return `jsonb_build_object(${keys.map(([key, column]) => `'${key}', ${row}.${column}`).join(", ")})`;
}

function projectJson(names: AiChatNames, row: string): string {
  const p = names.c.projects;
  return `jsonb_build_object('id', ${row}.${p.id}, 'organization_id', ${row}.${p.tenant}, 'owner_id', ${row}.${p.owner}, 'name', ${row}.${p.name}, 'instructions', ${row}.${p.instructions}, 'default_model', ${row}.${p.model}, 'pinned', ${row}.${p.pinned}, 'archived_at', ${row}.${p.archivedAt}, 'created_at', ${row}.${p.createdAt}, 'updated_at', ${row}.${p.updatedAt})`;
}

function chats(ctx: ModuleContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const p = names.c.projects;
  const m = names.c.messages;
  const can = canIn;
  const notFound = raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "%CHAT%");
  const ownProject = (project: string, owner: string, tenant: string): string =>
    `exists (select 1 from ${t.projects} pr where pr.${p.id} = ${project} and pr.${p.owner} = ${owner} and pr.${p.tenant} = ${tenant})`;

  return `-- Whether the caller may read a chat: its owner, the service role, or a
-- member with ${perm.read} when the chat is shared with the organization.
create or replace function ${fn("ai_chat_can_read")}(chat uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${t.chats} x
    where x.${ch.id} = ai_chat_can_read.chat
      and (
        ${SERVICE_CALLER}
        or x.${ch.owner} = (select auth.uid())
        or (x.${ch.visibility} = 'organization' and ${can(`x.${ch.tenant}`, perm.read)})
      )
  );
$$;
${userGrant(`${fn("ai_chat_can_read")}(uuid)`)}

-- Sends a payload-free event to a chat's topic and, with list, to its
-- owner's sidebar topic.
create or replace function ${fn("ai_chat_notify")}(chat uuid, owner uuid, event text, payload jsonb, list boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := coalesce(payload, '{}'::jsonb) || jsonb_build_object('chatId', chat);
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return;
  end if;
  perform realtime.send(v_payload, event, ${sqlString(`${names.topic}:`)} || chat::text, true);
  if list and owner is not null then
    perform realtime.send(v_payload, event, ${sqlString(`${names.listTopic}:`)} || owner::text, true);
  end if;
end;
$$;
revoke execute on function ${fn("ai_chat_notify")}(uuid, uuid, text, jsonb, boolean) from public, anon, authenticated;

-- Creates a chat for the caller in a tenant (${perm.create}). fields may set
-- id (a client-generated uuid, so a retry returns the same chat), title,
-- model, project_id, agent_id, visibility and is_temporary; the service
-- role also sets owner_id. Temporary chats expire after
-- ${names.temporaryTtl} and stay out of the sidebar.
create or replace function ${fn("create_ai_chat")}(tenant ${ctx.idType}, fields jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(create_ai_chat.fields, '{}'::jsonb);
  v_owner uuid := auth.uid();
  v_row ${t.chats};
  v_id uuid;
  v_project uuid := (v_fields ->> 'project_id')::uuid;
  v_temporary boolean := coalesce((v_fields ->> 'is_temporary')::boolean, false);
  v_visibility text := coalesce(v_fields ->> 'visibility', 'private');
begin
  if ${SERVICE_CALLER} then
    v_owner := coalesce((v_fields ->> 'owner_id')::uuid, v_owner);
  elsif not ${can("create_ai_chat.tenant", perm.create)} then
    ${raise("You may not start chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  if v_owner is null then
    ${raise("Sign in first", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  if v_visibility = 'organization' and not (${SERVICE_CALLER} or ${can("create_ai_chat.tenant", perm.share)}) then
    ${raise("You may not share chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  v_id := coalesce((v_fields ->> 'id')::uuid, gen_random_uuid());
  select * into v_row from ${t.chats} x where x.${ch.id} = v_id;
  if found then
    if v_row.${ch.owner} <> v_owner then
      ${raise("Chat % exists", "23505", "AI_CHAT_EXISTS", "v_id")}
    end if;
    return ${chatJson(names, "v_row")};
  end if;
  if v_project is not null and not ${ownProject("v_project", "v_owner", "create_ai_chat.tenant")} then
    ${raise("No project %", "P0002", "AI_PROJECT_NOT_FOUND", "v_project")}
  end if;
  insert into ${t.chats} (${ch.id}, ${ch.tenant}, ${ch.owner}, ${ch.project}, ${ch.agent}, ${ch.title}, ${ch.model}, ${ch.visibility}, ${ch.temporary}, ${ch.expiresAt})
  values (
    v_id, create_ai_chat.tenant, v_owner, v_project, v_fields ->> 'agent_id',
    coalesce(v_fields ->> 'title', ''), v_fields ->> 'model', v_visibility, v_temporary,
    case when v_temporary then now() + interval ${sqlString(names.temporaryTtl)} end
  )
  returning * into v_row;
  if not v_temporary then
    perform ${fn("ai_chat_notify")}(v_id, v_owner, 'chat.created', '{}'::jsonb, true);
  end if;
  return ${chatJson(names, "v_row")};
end;
$$;
${userGrant(`${fn("create_ai_chat")}(${ctx.idType}, jsonb)`)}

-- Changes the caller's chat. fields may set title, model, project_id,
-- agent_id, visibility (organization needs ${perm.share}), pinned,
-- archived, and is_temporary = false to keep a temporary chat.
create or replace function ${fn("update_ai_chat")}(chat uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(update_ai_chat.fields, '{}'::jsonb);
  v_row ${t.chats};
  v_project uuid := (v_fields ->> 'project_id')::uuid;
begin
  select * into v_row from ${t.chats} x where x.${ch.id} = update_ai_chat.chat for update;
  if not found or not (${SERVICE_CALLER} or v_row.${ch.owner} = (select auth.uid())) then
    ${notFound.replace("%CHAT%", "update_ai_chat.chat")}
  end if;
  if v_project is not null and not ${ownProject("v_project", `v_row.${ch.owner}`, `v_row.${ch.tenant}`)} then
    ${raise("No project %", "P0002", "AI_PROJECT_NOT_FOUND", "v_project")}
  end if;
  if v_fields ->> 'visibility' = 'organization' and v_row.${ch.visibility} <> 'organization'
    and not (${SERVICE_CALLER} or ${can(`v_row.${ch.tenant}`, perm.share)}) then
    ${raise("You may not share chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  update ${t.chats} x set
    ${ch.title} = case when v_fields ? 'title' then coalesce(v_fields ->> 'title', '') else x.${ch.title} end,
    ${ch.model} = case when v_fields ? 'model' then v_fields ->> 'model' else x.${ch.model} end,
    ${ch.project} = case when v_fields ? 'project_id' then v_project else x.${ch.project} end,
    ${ch.agent} = case when v_fields ? 'agent_id' then v_fields ->> 'agent_id' else x.${ch.agent} end,
    ${ch.visibility} = case when v_fields ? 'visibility' then coalesce(v_fields ->> 'visibility', 'private') else x.${ch.visibility} end,
    ${ch.pinned} = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x.${ch.pinned} end,
    ${ch.archivedAt} = case
      when not v_fields ? 'archived' then x.${ch.archivedAt}
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x.${ch.archivedAt}, now())
    end,
    ${ch.temporary} = x.${ch.temporary} and coalesce((v_fields ->> 'is_temporary')::boolean, true),
    ${ch.expiresAt} = case when x.${ch.temporary} and coalesce((v_fields ->> 'is_temporary')::boolean, true) then x.${ch.expiresAt} end,
    ${ch.updatedAt} = now()
  where x.${ch.id} = update_ai_chat.chat
  returning * into v_row;
  perform ${fn("ai_chat_notify")}(v_row.${ch.id}, v_row.${ch.owner}, 'chat.updated', '{}'::jsonb, not v_row.${ch.temporary});
  return ${chatJson(names, "v_row")};
end;
$$;
${userGrant(`${fn("update_ai_chat")}(uuid, jsonb)`)}

-- Deletes a chat with its messages; its owner, the service role or ${perm.admin}.
create or replace function ${fn("delete_ai_chat")}(chat uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t.chats};
begin
  select * into v_row from ${t.chats} x where x.${ch.id} = delete_ai_chat.chat for update;
  if not found then
    return false;
  end if;
  if not (${SERVICE_CALLER} or v_row.${ch.owner} = (select auth.uid()) or ${can(`v_row.${ch.tenant}`, perm.admin)}) then
    ${notFound.replace("%CHAT%", "delete_ai_chat.chat")}
  end if;
  delete from ${t.chats} x where x.${ch.id} = delete_ai_chat.chat;
  perform ${fn("ai_chat_notify")}(v_row.${ch.id}, v_row.${ch.owner}, 'chat.deleted', '{}'::jsonb, true);
  return true;
end;
$$;
${userGrant(`${fn("delete_ai_chat")}(uuid)`)}

create or replace function ${fn("get_ai_chat")}(chat uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t.chats};
begin
  if not ${fn("ai_chat_can_read")}(get_ai_chat.chat) then
    ${notFound.replace("%CHAT%", "get_ai_chat.chat")}
  end if;
  select * into v_row from ${t.chats} x where x.${ch.id} = get_ai_chat.chat;
  return ${chatJson(names, "v_row")};
end;
$$;
${userGrant(`${fn("get_ai_chat")}(uuid)`)}

-- The caller's chats, newest activity first: { items, next }. Pass next as
-- after for the following page. search matches titles and message text;
-- temporary chats never show.
create or replace function ${fn("list_ai_chats")}(tenant ${ctx.idType} default null, search text default null, project uuid default null, pinned boolean default null, archived boolean default false, after text default null, size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_query tsquery;
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(list_ai_chats.size, 50), 1), 200);
  v_items jsonb;
  v_next text;
begin
  if v_uid is null then
    return jsonb_build_object('items', '[]'::jsonb, 'next', null);
  end if;
  if nullif(btrim(list_ai_chats.search), '') is not null then
    v_query := websearch_to_tsquery('simple'::regconfig, list_ai_chats.search);
  end if;
  if list_ai_chats.after is not null then
    v_at := split_part(list_ai_chats.after, '|', 1)::timestamptz;
    v_id := split_part(list_ai_chats.after, '|', 2)::uuid;
  end if;
  select coalesce(jsonb_agg(${chatJson(names, "page")} order by page.${ch.lastMessageAt} desc, page.${ch.id} desc), '[]'::jsonb)
  into v_items
  from (
    select x.* from ${t.chats} x
    where x.${ch.owner} = v_uid
      and not x.${ch.temporary}
      and (list_ai_chats.tenant is null or x.${ch.tenant} = list_ai_chats.tenant)
      and (list_ai_chats.project is null or x.${ch.project} = list_ai_chats.project)
      and (list_ai_chats.pinned is null or x.${ch.pinned} = list_ai_chats.pinned)
      and (list_ai_chats.archived is null or (x.${ch.archivedAt} is not null) = list_ai_chats.archived)
      and (v_at is null or (x.${ch.lastMessageAt}, x.${ch.id}) < (v_at, v_id))
      and (
        v_query is null
        or x.${ch.search} @@ v_query
        or exists (select 1 from ${t.messages} mm where mm.${m.chat} = x.${ch.id} and mm.${m.search} @@ v_query)
      )
    order by x.${ch.lastMessageAt} desc, x.${ch.id} desc
    limit v_size + 1
  ) page;
  if jsonb_array_length(v_items) > v_size then
    v_items := v_items - v_size;
    v_next := (v_items -> (v_size - 1) ->> 'last_message_at') || '|' || (v_items -> (v_size - 1) ->> 'id');
  end if;
  return jsonb_build_object('items', v_items, 'next', v_next);
end;
$$;
${userGrant(`${fn("list_ai_chats")}(${ctx.idType}, text, uuid, boolean, boolean, text, integer)`)}

-- Creates a project (id null, needs ${perm.create}) or changes the caller's
-- own. fields may set name, instructions, default_model, pinned, archived.
create or replace function ${fn("save_ai_project")}(id uuid, tenant ${ctx.idType}, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(save_ai_project.fields, '{}'::jsonb);
  v_row ${t.projects};
begin
  if save_ai_project.id is null then
    if auth.uid() is null or not ${can("save_ai_project.tenant", perm.create)} then
      ${raise("You may not create projects here", "42501", "AI_CHAT_FORBIDDEN")}
    end if;
    insert into ${t.projects} (${p.tenant}, ${p.owner}, ${p.name}, ${p.instructions}, ${p.model}, ${p.pinned})
    values (
      save_ai_project.tenant, auth.uid(), v_fields ->> 'name', coalesce(v_fields ->> 'instructions', ''),
      v_fields ->> 'default_model', coalesce((v_fields ->> 'pinned')::boolean, false)
    )
    returning * into v_row;
    return ${projectJson(names, "v_row")};
  end if;
  update ${t.projects} x set
    ${p.name} = coalesce(v_fields ->> 'name', x.${p.name}),
    ${p.instructions} = case when v_fields ? 'instructions' then coalesce(v_fields ->> 'instructions', '') else x.${p.instructions} end,
    ${p.model} = case when v_fields ? 'default_model' then v_fields ->> 'default_model' else x.${p.model} end,
    ${p.pinned} = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x.${p.pinned} end,
    ${p.archivedAt} = case
      when not v_fields ? 'archived' then x.${p.archivedAt}
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x.${p.archivedAt}, now())
    end,
    ${p.updatedAt} = now()
  where x.${p.id} = save_ai_project.id and x.${p.owner} = (select auth.uid())
  returning * into v_row;
  if not found then
    ${raise("No project %", "P0002", "AI_PROJECT_NOT_FOUND", "save_ai_project.id")}
  end if;
  return ${projectJson(names, "v_row")};
end;
$$;
${userGrant(`${fn("save_ai_project")}(uuid, ${ctx.idType}, jsonb)`)}

-- Deletes the caller's project; its chats stay, outside any project.
create or replace function ${fn("delete_ai_project")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from ${t.projects} x where x.${p.id} = delete_ai_project.id and x.${p.owner} = (select auth.uid());
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${userGrant(`${fn("delete_ai_project")}(uuid)`)}

create or replace function ${fn("list_ai_projects")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${projectJson(names, "x")} order by x.${p.pinned} desc, x.${p.updatedAt} desc), '[]'::jsonb)
  from ${t.projects} x
  where x.${p.owner} = (select auth.uid()) and x.${p.tenant} = list_ai_projects.tenant;
$$;
${userGrant(`${fn("list_ai_projects")}(${ctx.idType})`)}`;
}

/**
 * The SQL functions of the `ai-chat` module: chats and projects here, the
 * message tree and streams in `messages()`, the rest in `aiChatExtras`.
 */
export function aiChatFunctions(
  ctx: ModuleContext,
  names: AiChatNames,
): string {
  return `${chats(ctx, names)}

${messages(ctx, names)}

${aiChatExtras(ctx, names)}`;
}

function messageJson(names: AiChatNames, row: string, native: string): string {
  const m = names.c.messages;
  return `jsonb_build_object('id', ${row}.${m.id}, 'parent_id', ${row}.${m.parent}, 'role', ${row}.${m.role}, 'parts', ${row}.${m.parts}, 'metadata', ${row}.${m.metadata}, 'format', ${row}.${m.format}, 'native', case when ${native} then ${row}.${m.native} end, 'model', ${row}.${m.model}, 'status', ${row}.${m.status}, 'created_at', ${row}.${m.createdAt})`;
}

function messages(ctx: ModuleContext, names: AiChatNames): string {
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
  if not found or not (${SERVICE_CALLER} or v_chat.${ch.owner} = (select auth.uid())) then
    ${raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", `${name}.chat`)}
  end if;`;
  const serviceOnly = raise(
    "Only the server saves replies",
    "42501",
    "AI_CHAT_FORBIDDEN",
  );
  const completed = ctx.emit({
    type: "ai_chat.message.completed",
    payload: `jsonb_build_object('chatId', v_chat.${ch.id}, 'messageId', v_id, 'organizationId', v_chat.${ch.tenant}::text, 'ownerId', v_chat.${ch.owner}, 'model', coalesce(save_ai_assistant_message.model, v_chat.${ch.model}), 'status', v_status)`,
    subject: `'ai-chats/' || v_chat.${ch.id}::text`,
    tenant: `v_chat.${ch.tenant}`,
    key: `'ai_chat.message.completed:' || v_chat.${ch.id}::text || ':' || v_id`,
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
    ${messageJson(names, "up", "ai_message_path_of.include_native")} || jsonb_build_object(
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
    v_parent := case when v_existing.${m.role} = 'user' then v_existing.${m.id} else v_existing.${m.parent} end;
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
  insert into ${t.messages} (${m.chat}, ${m.id}, ${m.parent}, ${m.owner}, ${m.role}, ${m.parts}, ${m.metadata})
  values (
    v_chat.${ch.id}, v_id, v_parent, v_chat.${ch.owner}, 'user', append_ai_user_message.message -> 'parts',
    case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else '{}'::jsonb end
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
#variable_conflict use_variable
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
  insert into ${t.messages} (${m.chat}, ${m.id}, ${m.parent}, ${m.owner}, ${m.role}, ${m.parts}, ${m.metadata}, ${m.format}, ${m.native}, ${m.model}, ${m.status})
  values (
    v_chat.${ch.id}, v_id, save_ai_assistant_message.parent_id, v_chat.${ch.owner}, v_role,
    save_ai_assistant_message.message -> 'parts',
    case when jsonb_typeof(save_ai_assistant_message.message -> 'metadata') = 'object' then save_ai_assistant_message.message -> 'metadata' else '{}'::jsonb end,
    coalesce(save_ai_assistant_message.format, 'canonical'), save_ai_assistant_message.native,
    save_ai_assistant_message.model, v_status
  )
  on conflict (${m.chat}, ${m.id}) do update set
    ${m.parts} = excluded.${m.parts},
    ${m.metadata} = excluded.${m.metadata},
    ${m.format} = excluded.${m.format},
    ${m.native} = excluded.${m.native},
    ${m.model} = coalesce(excluded.${m.model}, ${t.messages}.${m.model}),
    ${m.status} = excluded.${m.status}
  returning (xmax = 0) into v_created;
  delete from ${t.sources} x where x.${s.chat} = v_chat.${ch.id} and x.${s.message} = v_id;
  insert into ${t.sources} (${s.chat}, ${s.message}, ${s.source}, ${s.kind}, ${s.url}, ${s.title}, ${s.metadata})
  select distinct on (e ->> 'id') v_chat.${ch.id}, v_id, e ->> 'id', coalesce(e ->> 'sourceType', 'url'), e ->> 'url', e ->> 'title', e -> 'providerMetadata'
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
create or replace function ${fn("claim_ai_chat_stream")}(chat uuid, stream text, model text default null, message_id text default null, engine text default 'ai-sdk')
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
      and v_run.${r.status} in ('queued', 'running', 'cancel_requested')
      and v_run.${r.startedAt} > now() - interval ${sqlString(names.staleAfter)}
      and not exists (
        select 1 from ${streams.table("streams")} so
        where so.${st("id")} = v_chat.${ch.activeStream} and so.${st("closedAt")} is not null
      ) then
      return jsonb_build_object('claimed', false, 'stream_id', v_chat.${ch.activeStream}, 'run_id', v_chat.${ch.activeRun});
    end if;
    update ${t.runs} x set ${r.status} = 'stopped', ${r.endedAt} = now()
    where x.${r.id} = v_chat.${ch.activeRun} and x.${r.endedAt} is null;
  end if;
  insert into ${t.runs} (${r.chat}, ${r.owner}, ${r.message}, ${r.stream}, ${r.engine}, ${r.model})
  values (v_chat.${ch.id}, v_chat.${ch.owner}, claim_ai_chat_stream.message_id, claim_ai_chat_stream.stream, coalesce(claim_ai_chat_stream.engine, 'ai-sdk'), coalesce(claim_ai_chat_stream.model, v_chat.${ch.model}))
  returning ${r.id} into v_run_id;
  update ${t.chats} x set ${ch.activeStream} = claim_ai_chat_stream.stream, ${ch.activeRun} = v_run_id, ${ch.updatedAt} = now()
  where x.${ch.id} = v_chat.${ch.id};
  perform ${fn("ai_chat_notify")}(v_chat.${ch.id}, null, 'stream.started', jsonb_build_object('streamId', claim_ai_chat_stream.stream, 'runId', v_run_id), false);
  return jsonb_build_object('claimed', true, 'stream_id', claim_ai_chat_stream.stream, 'run_id', v_run_id);
end;
$$;
${serviceGrant(`${fn("claim_ai_chat_stream")}(uuid, text, text, text, text)`)}

-- Ends the claim when the stream finished (the service role only) and
-- records the run's status, usage, gateway generation id and cost.
create or replace function ${fn("release_ai_chat_stream")}(chat uuid, stream text, status text default 'done', usage jsonb default null, generation_id text default null, error text default null, cost_micro_usd bigint default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_status text := coalesce(release_ai_chat_stream.status, 'done');
  v_found boolean := false;
begin
  if not ${SERVICE_CALLER} then
    ${serviceOnly}
  end if;
  if v_status not in ('done', 'error', 'stopped') then
    ${raise("A run ends done, error or stopped, not %", "22023", "AI_RUN_INVALID", "v_status")}
  end if;
  update ${t.runs} x set
    ${r.status} = v_status,
    ${r.usage} = coalesce(release_ai_chat_stream.usage, x.${r.usage}),
    ${r.generation} = coalesce(release_ai_chat_stream.generation_id, x.${r.generation}),
    ${r.error} = release_ai_chat_stream.error,
    ${r.cost} = coalesce(release_ai_chat_stream.cost_micro_usd, x.${r.cost}),
    ${r.endedAt} = coalesce(x.${r.endedAt}, now())
  where x.${r.chat} = release_ai_chat_stream.chat and x.${r.stream} = release_ai_chat_stream.stream;
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
  update ${t.runs} x set ${r.status} = 'cancel_requested'
  where x.${r.id} = v_chat.${ch.activeRun} and x.${r.status} in ('queued', 'running');
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
  update ${t.runs} x set
    ${r.cost} = set_ai_run_cost.cost_micro_usd,
    ${r.usage} = x.${r.usage} || coalesce(set_ai_run_cost.usage, '{}'::jsonb)
  where x.${r.generation} = set_ai_run_cost.generation_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
${serviceGrant(`${fn("set_ai_run_cost")}(text, bigint, jsonb)`)}`;
}
