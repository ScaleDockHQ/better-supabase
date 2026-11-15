import type { BlockSqlContext } from "../context.ts";
import type { AiChatNames } from "./ai-chat.ts";

import {
  filterAny,
  filterFirst,
  filterHasInvalid,
  filterSet,
  listBody,
  listDeclare,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { participatesIn } from "./ai-chat-tables.ts";

/** What `aiChatFunctions` hands the page functions. */
export interface AiChatPageDeps {
  readonly chatJson: (row: string) => string;
  readonly projectJson: (row: string) => string;
}

/**
 * `page_ai_chats`, `page_ai_projects` and `get_ai_project`: the keyset pages
 * and the project read of the block list contract (ADR 1077). The chat page
 * reads the caller's chats and the ones they take part in, as `list_ai_chats`.
 */
export function aiChatPagesSql(
  ctx: BlockSqlContext,
  names: AiChatNames,
  deps: AiChatPageDeps,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const { t } = names;
  const ch = names.c.chats;
  const p = names.c.projects;
  const m = names.c.messages;
  const id = ctx.idType;

  const chatIdKey = { expr: `x.${ch.id}`, dir: "desc", type: "uuid" } as const;
  const projectIdKey = { expr: `x.${p.id}`, dir: "asc", type: "uuid" } as const;

  const pinned = ctx.has("chats", "pinned") ? `x.${ch.pinned}` : "false";

  const archived = ctx.has("chats", "archivedAt")
    ? `(x.${ch.archivedAt} is not null)`
    : "false";

  const chatCreated = ctx.has("chats", "createdAt")
    ? `x.${ch.createdAt}`
    : "'epoch'::timestamptz";

  const projectUpdated = ctx.has("projects", "updatedAt")
    ? `x.${p.updatedAt}`
    : "'epoch'::timestamptz";

  const recent = [
    { expr: `x.${ch.lastMessageAt}`, dir: "desc", type: "timestamptz" },
    chatIdKey,
  ] as const;

  const chatPage = {
    name: "page_ai_chats",
    from: t.chats,
    alias: "x",
    where: [
      `(x.${ch.owner} = v_uid or ${participatesIn(ctx, names, "x")})`,
      `not x.${ch.temporary}`,
      `x.${ch.tenant} = page_ai_chats.tenant`,
      `(v_project is null or x.${ch.project} = v_project::uuid)`,
      filterAny("pinned", `${pinned}::text`),
      // Archived chats stay out unless the caller names the archived filter.
      `(case when ${filterSet("archived")} then ${filterAnyArchived(archived)} else not ${archived} end)`,
      `(v_query is null or x.${ch.search} @@ v_query
        or exists (select 1 from ${t.messages} mm where mm.${m.chat} = x.${ch.id} and mm.${m.search} @@ v_query))`,
    ],
    keys: recent,
    sorts: {
      lastMessageAt: recent,
      createdAt: [
        { expr: chatCreated, dir: "desc", type: "timestamptz" },
        chatIdKey,
      ],
      title: [
        {
          expr: `lower(coalesce(x.${ch.title}, ''))`,
          dir: "asc",
          type: "text",
        },
        chatIdKey,
      ],
    },
    facets: { pinned, archived },
    rowJson: deps.chatJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("AI_CHAT_INVALID", message, "22023"),
  } as const;

  const projectPinned = ctx.has("projects", "pinned")
    ? `x.${p.pinned}`
    : "false";

  const projectArchived = ctx.has("projects", "archivedAt")
    ? `(x.${p.archivedAt} is not null)`
    : "false";

  const projectKeys = [
    ...(ctx.has("projects", "pinned")
      ? [{ expr: projectPinned, dir: "desc", type: "boolean" } as const]
      : []),
    { expr: projectUpdated, dir: "desc", type: "timestamptz" } as const,
    projectIdKey,
  ];

  const projectPage = {
    name: "page_ai_projects",
    from: t.projects,
    alias: "x",
    where: [
      `x.${p.owner} = v_uid`,
      `x.${p.tenant} is not distinct from page_ai_projects.tenant`,
      filterAny("pinned", `${projectPinned}::text`),
      `(case when ${filterSet("archived")} then ${filterAnyArchived(projectArchived)} else not ${projectArchived} end)`,
      `(v_search is null or x.${p.name} ilike v_search)`,
    ],
    keys: projectKeys,
    sorts: {
      updatedAt: [
        { expr: projectUpdated, dir: "desc", type: "timestamptz" },
        projectIdKey,
      ],
      name: [
        { expr: `lower(x.${p.name})`, dir: "asc", type: "text" },
        projectIdKey,
      ],
    },
    facets: { pinned: projectPinned, archived: projectArchived },
    rowJson: deps.projectJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("AI_CHAT_INVALID", message, "22023"),
  } as const;

  return `-- The caller's chats and the chats they take part in, in a tenant, as a keyset
-- page (ADR 1077), newest activity first. filters is { projectId (one uuid),
-- pinned, archived (a value or a list of 'true' and 'false'; without archived
-- the archived chats stay out), search (titles and message text), sort
-- (lastMessageAt, createdAt, title), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }. Temporary chats never show.
create or replace function ${fn("page_ai_chats")}(tenant ${id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_filters jsonb := coalesce(page_ai_chats.filters, '{}'::jsonb);
  v_project text := ${filterFirst("projectId")};
  v_query tsquery;
  ${listDeclare(chatPage)}
begin
  if v_uid is null then
    return case when v_paged then jsonb_build_object('items', '[]'::jsonb, 'hasMore', false, 'nextCursor', null) else '[]'::jsonb end;
  end if;
  if ${filterHasInvalid("projectId")} then
    ${fail("AI_CHAT_INVALID", "projectId is a uuid", "22023")}
  end if;
  if nullif(btrim(v_filters ->> 'search'), '') is not null then
    v_query := websearch_to_tsquery('simple'::regconfig, v_filters ->> 'search');
  end if;
  ${listBody(chatPage)}
end;
$$;
${userGrant(`${fn("page_ai_chats")}(${id}, jsonb)`)}

-- The caller's projects in a tenant as a keyset page (ADR 1077), pinned first,
-- then the most recently changed. filters is { pinned, archived (a value or a
-- list of 'true' and 'false'; without archived the archived projects stay
-- out), search (name), sort (updatedAt, name), direction, facet, count,
-- limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_ai_projects")}(tenant ${id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_uid uuid := (select auth.uid());
  v_filters jsonb := coalesce(page_ai_projects.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%' end;
  ${listDeclare(projectPage)}
begin
  if v_uid is null then
    return case when v_paged then jsonb_build_object('items', '[]'::jsonb, 'hasMore', false, 'nextCursor', null) else '[]'::jsonb end;
  end if;
  ${listBody(projectPage)}
end;
$$;
${userGrant(`${fn("page_ai_projects")}(${id}, jsonb)`)}

-- One of the caller's projects, or null.
create or replace function ${fn("get_ai_project")}(id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${deps.projectJson("x")} from ${t.projects} x
  where x.${p.id} = get_ai_project.id and x.${p.owner} = (select auth.uid())
$$;
${userGrant(`${fn("get_ai_project")}(uuid)`)}`;
}

/** Whether an `archived` filter holds one of the wanted flags. */
function filterAnyArchived(flag: string): string {
  return filterAny("archived", `${flag}::text`);
}
