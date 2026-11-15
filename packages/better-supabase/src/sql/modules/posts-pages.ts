import type { BlockSqlContext } from "../context.ts";
import type { ListSortKey } from "../list-template.ts";

import {
  filterAny,
  filterFlag,
  filterHasInvalid,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { userGrant } from "../shared.ts";
import { asText } from "./over-app.ts";
import { postsSql } from "./posts-sql.ts";

/**
 * `page_posts` and `page_post_boards`: the posts and the boards as keyset pages
 * (ADR 1077). A post page reads the vote tally and the caller's vote with each
 * row, as `get_post` does.
 */
export function postPageFunctions(ctx: BlockSqlContext): string {
  const q = postsSql(ctx);
  const { fn, p, b, posts, boards, subject, reactions } = q;
  const sc = (column: string): string => reactions.col("scores", column);
  const rc = (column: string): string => reactions.col("reactions", column);
  const status = asText(ctx, "posts", `x.${p("status")}`);

  const idKey = { expr: `x.${p("id")}`, dir: "asc", type: "uuid" } as const;

  const created: ListSortKey = {
    expr: `x.${p("createdAt")}`,
    dir: "desc",
    type: "timestamptz",
  };

  const pinned: readonly ListSortKey[] = q.hasPost("pinnedAt")
    ? [
        {
          expr: `coalesce(x.${p("pinnedAt")}, '-infinity'::timestamptz)`,
          dir: "desc",
          type: "timestamptz",
        },
      ]
    : [];

  const activity: ListSortKey = {
    expr: q.hasPost("lastActivityAt")
      ? `coalesce(x.${p("lastActivityAt")}, x.${p("createdAt")})`
      : `x.${p("createdAt")}`,
    dir: "desc",
    type: "timestamptz",
  };

  const activeKeys = [...pinned, activity, idKey];

  // The score joins in a derived table, so a keyset key can read it.
  const scored = `(select t.*, coalesce(s.${sc("score")}, 0) as vote_score, coalesce(s.${sc("up")}, 0) as vote_up, coalesce(s.${sc("down")}, 0) as vote_down
    from ${posts} t
    left join ${reactions.table("scores")} s on s.${sc("tenant")} = t.${p("tenant")} and s.${sc("subjectType")} = ${subject} and s.${sc("subjectId")} = t.${p("id")}::text)`;

  const postPage = {
    name: "page_posts",
    from: scored,
    alias: "x",
    where: [
      `x.${p("tenant")} = page_posts.tenant`,
      filterAny("boardId", `x.${p("board")}`, "uuid"),
      filterAny("status", status),
      filterAny("authorId", `x.${p("author")}`, "uuid"),
      `(${filterFlag("merged")} or x.${p("mergedInto")} is null)`,
      ...(q.hasPost("archivedAt")
        ? [
            `(case when v_archived then x.${p("archivedAt")} is not null else x.${p("archivedAt")} is null end)`,
          ]
        : []),
      `(v_search is null or x.${p("title")} ilike v_search or x.${p("body")} ilike v_search)`,
    ],
    keys: activeKeys,
    sorts: {
      active: activeKeys,
      new: [created, idKey],
      top: [
        { expr: "x.vote_score", dir: "desc", type: "integer" },
        created,
        idKey,
      ],
    },
    facets: { status, boardId: `x.${p("board")}` },
    rowJson: `${q.postJson("x")} || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r.${rc("value")} from ${reactions.table("reactions")} r
      where r.${rc("tenant")} = x.${p("tenant")} and r.${rc("subjectType")} = ${subject}
        and r.${rc("subjectId")} = x.${p("id")}::text and r.${rc("kind")} = 'vote'
        and r.${rc("user")} = (select auth.uid())
    ), 0)))`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => q.invalid(message),
  } as const;

  const boardIdKey = {
    expr: `x.${b("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const boardNameKeys = [
    { expr: `x.${b("name")}`, dir: "asc", type: "text" },
    boardIdKey,
  ] as const;

  const boardPage = {
    name: "page_post_boards",
    from: boards,
    alias: "x",
    where: [
      `x.${b("tenant")} = page_post_boards.tenant`,
      ...(q.hasBoard("archivedAt")
        ? [`(${filterFlag("archived")} or x.${b("archivedAt")} is null)`]
        : []),
      filterAny("kind", asText(ctx, "boards", `x.${b("kind")}`)),
      `(v_search is null or x.${b("name")} ilike v_search${q.hasBoard("description") ? ` or x.${b("description")} ilike v_search` : ""})`,
    ],
    keys: boardNameKeys,
    sorts: {
      name: boardNameKeys,
      createdAt: [
        { expr: `x.${b("createdAt")}`, dir: "desc", type: "timestamptz" },
        boardIdKey,
      ],
    },
    facets: { kind: asText(ctx, "boards", `x.${b("kind")}`) },
    rowJson: q.boardJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => q.invalid(message),
  } as const;

  return `-- Posts the caller reads as a keyset page (ADR 1077). filters is { boardId,
-- status, authorId (each a value or a list), merged (true includes merged
-- posts), archived (true reads only archived posts), search (title, body),
-- sort (active, new, top; active by default: pinned first, then the latest
-- activity), direction, facet (status, boardId), count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function ${fn("page_posts")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_posts.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_archived boolean := ${filterFlag("archived")};
  ${listDeclare(postPage)}
begin
  if ${filterHasInvalid("boardId")} or ${filterHasInvalid("authorId")} then
    ${q.invalid("boardId and authorId are uuids")}
  end if;
  ${listBody(postPage)}
end;
$$;
${userGrant(`${fn("page_posts")}(${ctx.idType}, jsonb)`)}

-- The organization's boards as a keyset page (ADR 1077), by name. filters is
-- { archived (true also reads archived boards), kind (a value or a list),
-- search (name, description), sort (name, createdAt), direction, facet (kind),
-- count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_post_boards")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_post_boards.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(boardPage)}
begin
  ${listBody(boardPage)}
end;
$$;
${userGrant(`${fn("page_post_boards")}(${ctx.idType}, jsonb)`)}
`;
}
