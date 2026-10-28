import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";
import type { AiChatNames } from "./ai-chat.ts";

import { sqlString } from "../../core/template.ts";
import {
  extraFieldsJson,
  raise,
  replaceColumnCheck,
  SERVICE_CALLER,
  userGrant,
  pageSize,
  writeExtraColumns,
} from "../shared.ts";
import { aiChatExtras } from "./ai-chat-extras.ts";
import { aiChatMessages } from "./ai-chat-messages.ts";
import { aiChatParticipants } from "./ai-chat-participants.ts";
import {
  asText,
  assignments,
  columnOr,
  participates,
  rowJson,
  writtenPairs,
  AI_RUN_STATES,
} from "./ai-chat-tables.ts";

/**
 * `jsonb_build_object` of a chat row, with stable keys whatever the column
 * names.
 */
function chatJson(
  ctx: BlockSqlContext,
  names: AiChatNames,
  row: string,
): string {
  return rowJson(
    ctx,
    "chats",
    row,
    [
      ["id", "id"],
      ["organization_id", "tenant"],
      ["owner_id", "owner"],
      ["project_id", "project"],
      ["agent_id", "agent"],
      ["title", "title"],
      ["model", "model"],
      ["visibility", "visibility"],
      ["pinned", "pinned", "false"],
      ["archived_at", "archivedAt"],
      ["is_temporary", "temporary"],
      ["expires_at", "expiresAt"],
      ["current_leaf_id", "leaf"],
      ["active_stream_id", "activeStream"],
      ["active_run_id", "activeRun"],
      ["last_message_at", "lastMessageAt"],
      ["created_at", "createdAt"],
      ["updated_at", "updatedAt"],
    ],
    extraFieldsJson(row, names.chatExtras),
  );
}

function projectJson(ctx: BlockSqlContext, row: string): string {
  return rowJson(ctx, "projects", row, [
    ["id", "id"],
    ["organization_id", "tenant"],
    ["owner_id", "owner"],
    ["name", "name"],
    ["instructions", "instructions"],
    ["default_model", "model"],
    ["pinned", "pinned", "false"],
    ["archived_at", "archivedAt"],
    ["created_at", "createdAt"],
    ["updated_at", "updatedAt"],
  ]);
}

/** The `archived` field of an update, kept in an `archived_at` column. */
function archivedValue(column: string): string {
  return `case
      when not v_fields ? 'archived' then ${column}
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(${column}, now())
    end`;
}

const PINNED =
  "case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else %s end";

function chats(ctx: BlockSqlContext, names: AiChatNames): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t, perm } = names;
  const ch = names.c.chats;
  const p = names.c.projects;
  const m = names.c.messages;

  const can = (tenant: string, permission: string): string =>
    ctx.scope.can(tenant, permission);

  /**
   * `can`, or with `options.tenant: false` any signed-in caller when `tenant`
   * is null: a chat or project outside every tenant is its owner's alone.
   */
  const mayCreate = (tenant: string, permission: string): string =>
    names.tenantless
      ? `(case when ${tenant} is null then (select auth.uid()) is not null else ${can(tenant, permission)} end)`
      : can(tenant, permission);

  const noTenant = raise(
    "A chat outside a tenant stays private",
    "22023",
    "AI_CHAT_NO_TENANT",
  );

  const notFound = raise("No chat %", "P0002", "AI_CHAT_NOT_FOUND", "%CHAT%");

  const visibility = (row: string): string =>
    asText(ctx, "chats", `${row}.${ch.visibility}`);

  const [chatColumns, chatValues] = writtenPairs(ctx, "chats", [
    ["id", "\n    v_id"],
    ["tenant", "create_ai_chat.tenant"],
    ["owner", "v_owner"],
    ["project", "v_project"],
    ["agent", "v_fields ->> 'agent_id'"],
    ["title", "\n    coalesce(v_fields ->> 'title', '')"],
    ["model", "v_fields ->> 'model'"],
    ["visibility", ctx.cast("chats", "visibility", "v_visibility")],
    ["temporary", "v_temporary"],
    [
      "expiresAt",
      `\n    case when v_temporary then now() + interval ${sqlString(names.temporaryTtl)} end`,
    ],
  ]);

  const [projectColumns, projectValues] = writtenPairs(ctx, "projects", [
    ["tenant", "\n      save_ai_project.tenant"],
    ["owner", "auth.uid()"],
    ["name", "v_fields ->> 'name'"],
    ["instructions", "coalesce(v_fields ->> 'instructions', '')"],
    ["model", "\n      v_fields ->> 'default_model'"],
    ["pinned", "coalesce((v_fields ->> 'pinned')::boolean, false)"],
  ]);

  const flags = (table: string, row: string): string =>
    assignments(ctx, table, [
      [
        "pinned",
        () => PINNED.replace("%s", columnOr(ctx, table, row, "pinned")),
      ],
      [
        "archivedAt",
        () => archivedValue(columnOr(ctx, table, row, "archivedAt")),
      ],
    ]);

  const ownProject = (project: string, owner: string, tenant: string): string =>
    `exists (select 1 from ${t.projects} pr where pr.${p.id} = ${project} and pr.${p.owner} = ${owner} and pr.${p.tenant} is not distinct from ${tenant})`;

  return `-- Whether the caller may read a chat: its owner, the service role, a
-- participant, or a member with ${perm.read} when the chat is shared with
-- the organization.
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
        or (${visibility("x")} = 'organization' and ${can(`x.${ch.tenant}`, perm.read)})
        or ${participates(names, `x.${ch.id}`)}
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
  elsif not ${mayCreate("create_ai_chat.tenant", perm.create)} then
    ${raise("You may not start chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  if v_owner is null then
    ${raise("Sign in first", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  if v_visibility = 'organization' and create_ai_chat.tenant is null then
    ${noTenant}
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
    return ${chatJson(ctx, names, "v_row")};
  end if;
  if v_project is not null and not ${ownProject("v_project", "v_owner", "create_ai_chat.tenant")} then
    ${raise("No project %", "P0002", "AI_PROJECT_NOT_FOUND", "v_project")}
  end if;
  insert into ${t.chats} (${chatColumns})
  values (${chatValues}
  )
  returning * into v_row;${writeExtraColumns(t.chats, names.chatExtras, "v_fields", `x.${ch.id} = v_row.${ch.id}`, "v_row")}
  if not v_temporary then
    perform ${fn("ai_chat_notify")}(v_id, v_owner, 'chat.created', '{}'::jsonb, true);
  end if;
  return ${chatJson(ctx, names, "v_row")};
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
  if not found or not (${SERVICE_CALLER} or coalesce(v_row.${ch.owner} = (select auth.uid()), false)) then
    ${notFound.replace("%CHAT%", "update_ai_chat.chat")}
  end if;
  if v_project is not null and not ${ownProject("v_project", `v_row.${ch.owner}`, `v_row.${ch.tenant}`)} then
    ${raise("No project %", "P0002", "AI_PROJECT_NOT_FOUND", "v_project")}
  end if;
  if v_fields ->> 'visibility' = 'organization' and v_row.${ch.tenant} is null then
    ${noTenant}
  end if;
  if v_fields ->> 'visibility' = 'organization' and ${visibility("v_row")} <> 'organization'
    and not (${SERVICE_CALLER} or ${can(`v_row.${ch.tenant}`, perm.share)}) then
    ${raise("You may not share chats here", "42501", "AI_CHAT_FORBIDDEN")}
  end if;
  update ${t.chats} x set
    ${ch.title} = case when v_fields ? 'title' then coalesce(v_fields ->> 'title', '') else x.${ch.title} end,
    ${ch.model} = case when v_fields ? 'model' then v_fields ->> 'model' else x.${ch.model} end,
    ${ch.project} = case when v_fields ? 'project_id' then v_project else x.${ch.project} end,${assignments(
      ctx,
      "chats",
      [
        [
          "agent",
          () =>
            `case when v_fields ? 'agent_id' then v_fields ->> 'agent_id' else x.${ch.agent} end`,
        ],
      ],
    )}
    ${ch.visibility} = case when v_fields ? 'visibility' then ${ctx.cast("chats", "visibility", "coalesce(v_fields ->> 'visibility', 'private')")} else x.${ch.visibility} end,${flags("chats", "x")}
    ${ch.temporary} = x.${ch.temporary} and coalesce((v_fields ->> 'is_temporary')::boolean, true),
    ${ch.expiresAt} = case when x.${ch.temporary} and coalesce((v_fields ->> 'is_temporary')::boolean, true) then x.${ch.expiresAt} end,
    ${ch.updatedAt} = now()
  where x.${ch.id} = update_ai_chat.chat
  returning * into v_row;${writeExtraColumns(t.chats, names.chatExtras, "v_fields", `x.${ch.id} = v_row.${ch.id}`, "v_row")}
  perform ${fn("ai_chat_notify")}(v_row.${ch.id}, v_row.${ch.owner}, 'chat.updated', '{}'::jsonb, not v_row.${ch.temporary});
  return ${chatJson(ctx, names, "v_row")};
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
  if not (${SERVICE_CALLER} or coalesce(v_row.${ch.owner} = (select auth.uid()), false) or ${can(`v_row.${ch.tenant}`, perm.admin)}) then
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
  return ${chatJson(ctx, names, "v_row")};
end;
$$;
${userGrant(`${fn("get_ai_chat")}(uuid)`)}

-- The caller's chats and the chats they take part in, newest activity first:
-- { items, next }. Pass next as after for the following page. search matches titles and message text;
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
  v_size integer := ${pageSize("list_ai_chats.size", 50, 200)};
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
  select coalesce(jsonb_agg(${chatJson(ctx, names, "page")} order by page.${ch.lastMessageAt} desc, page.${ch.id} desc), '[]'::jsonb)
  into v_items
  from (
    select x.* from ${t.chats} x
    where (x.${ch.owner} = v_uid or ${participates(names, `x.${ch.id}`)})
      and not x.${ch.temporary}
      and (list_ai_chats.tenant is null or x.${ch.tenant} = list_ai_chats.tenant)
      and (list_ai_chats.project is null or x.${ch.project} = list_ai_chats.project)
      and (list_ai_chats.pinned is null or ${ctx.has("chats", "pinned") ? `x.${ch.pinned} = list_ai_chats.pinned` : "not list_ai_chats.pinned"})
      and (list_ai_chats.archived is null or ${ctx.has("chats", "archivedAt") ? `(x.${ch.archivedAt} is not null) = list_ai_chats.archived` : "not list_ai_chats.archived"})
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
-- own. fields may set name, instructions, default_model, pinned, archived${names.extras.projects.length > 0 ? ",\n-- and the app's extra columns" : ""}.
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
    if auth.uid() is null or not ${mayCreate("save_ai_project.tenant", perm.create)} then
      ${raise("You may not create projects here", "42501", "AI_CHAT_FORBIDDEN")}
    end if;
    insert into ${t.projects} (${projectColumns})
    values (${projectValues}
    )
    returning * into v_row;${writeExtraColumns(t.projects, names.extras.projects, "v_fields", `x.${p.id} = v_row.${p.id}`, "v_row")}
    return ${projectJson(ctx, "v_row")};
  end if;
  update ${t.projects} x set
    ${p.name} = coalesce(v_fields ->> 'name', x.${p.name}),
    ${p.instructions} = case when v_fields ? 'instructions' then coalesce(v_fields ->> 'instructions', '') else x.${p.instructions} end,
    ${p.model} = case when v_fields ? 'default_model' then v_fields ->> 'default_model' else x.${p.model} end,${flags("projects", "x")}
    ${p.updatedAt} = now()
  where x.${p.id} = save_ai_project.id and x.${p.owner} = (select auth.uid())
  returning * into v_row;
  if not found then
    ${raise("No project %", "P0002", "AI_PROJECT_NOT_FOUND", "save_ai_project.id")}
  end if;${writeExtraColumns(t.projects, names.extras.projects, "v_fields", `x.${p.id} = v_row.${p.id}`, "v_row")}
  return ${projectJson(ctx, "v_row")};
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
  select coalesce(jsonb_agg(${projectJson(ctx, "x")} order by ${ctx.has("projects", "pinned") ? `x.${p.pinned} desc, ` : ""}x.${p.updatedAt} desc), '[]'::jsonb)
  from ${t.projects} x
  where x.${p.owner} = (select auth.uid()) and x.${p.tenant} is not distinct from list_ai_projects.tenant;
$$;
${userGrant(`${fn("list_ai_projects")}(${ctx.idType})`)}`;
}

/**
 * The SQL functions of the `ai-chat` module: chats and projects here, the
 * message tree and streams in `messages()`, the rest in `aiChatExtras`.
 */
export function aiChatFunctions(
  ctx: BlockSqlContext,
  names: AiChatNames,
  layout: BlockSqlLayout,
): string {
  return `${chats(ctx, names)}

${aiChatParticipants(ctx, names)}

${aiChatMessages(ctx, names)}

${aiChatExtras(ctx, names, layout)}`;
}

// Version 1 ended runs done, error or stopped; version 2 uses the words
// ai-schedules and workflow runs use.
export function upgradeRunStates(ctx: BlockSqlContext): string {
  if (!ctx.owns("runs")) {
    return "";
  }

  const runs = ctx.table("runs");
  const status = ctx.col("runs", "status");

  return `${replaceColumnCheck({
    table: runs,
    column: status,
    name: "ai_runs_status_check",
    expression: `${status} in (${AI_RUN_STATES}, 'done', 'error', 'stopped')`,
  })}
update ${runs} set ${status} = case ${status}
  when 'done' then 'completed' when 'error' then 'failed' else 'cancelled' end
where ${status} in ('done', 'error', 'stopped');
${replaceColumnCheck({
  table: runs,
  column: status,
  name: "ai_runs_status_check",
  expression: `${status} in (${AI_RUN_STATES})`,
})}`;
}
