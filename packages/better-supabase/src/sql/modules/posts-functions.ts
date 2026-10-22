import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  pageSize,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { postsSql } from "./posts-sql.ts";

const KEY = "^[a-z0-9][a-z0-9_-]{0,62}$";

function boardFunctions(ctx: ModuleContext): string {
  const q = postsSql(ctx);
  const { fn, b, boards, invalid, forbidden, boardMissing, boardJson } = q;

  const saved = ctx.record({
    type: "post_board.saved",
    payload: `jsonb_build_object('organizationId', v_row.${b("tenant")}, 'id', v_row.${b("id")}, 'key', v_row.${b("key")}, 'kind', v_row.${b("kind")})`,
    subject: `'post-boards/' || v_row.${b("id")}::text`,
    tenant: `v_row.${b("tenant")}`,
    audit: {
      category: "data",
      targetType: "post_board",
      recordId: `v_row.${b("id")}::text`,
      targetLabel: `v_row.${b("name")}`,
      summary: sqlString("saved a board"),
    },
  });

  return `-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function ${fn("save_post_board")}(tenant ${ctx.idType}, board jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old ${boards};
  v_row ${boards};
  v_key text;
  v_name text;
  v_kind text;
begin
  if not ${q.allowed("save_post_board.tenant", q.manage)} then
    ${forbidden("not allowed to manage boards")}
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    ${invalid("board must be an object")}
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${boards} x where x.${b("id")} = v_id and x.${b("tenant")} = save_post_board.tenant for update;
    if v_old.${b("id")} is null then
      ${boardMissing}
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old.${b("key")} then
      ${invalid("a board's key can't change")}
    end if;
  end if;
  v_key := coalesce(v_old.${b("key")}, save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old.${b("name")});
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old.${b("kind")}, 'forum');
  if v_key is null or v_key !~ ${sqlString(KEY)} then
    ${invalid("a board needs a key of lowercase letters, digits, dashes and underscores")}
  end if;
  if v_name is null or length(v_name) > 200 then
    ${invalid("a board needs a name of at most 200 characters")}
  end if;
  if v_kind not in ('forum', 'feedback') then
    ${invalid("a board's kind is forum or feedback")}
  end if;
  if v_old.${b("id")} is null then
    insert into ${boards} (${b("tenant")}, ${b("key")}, ${b("name")}, ${b("description")}, ${b("kind")}, ${b("archivedAt")}, ${b("createdBy")})
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update ${boards} x set
      ${b("name")} = v_name,
      ${b("description")} = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x.${b("description")} end,
      ${b("kind")} = v_kind,
      ${b("archivedAt")} = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x.${b("archivedAt")}, now()) end else x.${b("archivedAt")} end,
      ${b("updatedAt")} = now()
    where x.${b("id")} = v_old.${b("id")}
    returning * into v_row;
  end if;
  ${saved}
  return ${boardJson("v_row")};
end;
$$;
${userGrant(`${fn("save_post_board")}(${ctx.idType}, jsonb)`)}

-- The organization's boards by name; archived ones only when asked.
create or replace function ${fn("list_post_boards")}(tenant ${ctx.idType}, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${boardJson("x")} order by x.${b("name")}, x.${b("id")}), '[]'::jsonb)
  from ${boards} x
  where x.${b("tenant")} = list_post_boards.tenant
    and (coalesce(list_post_boards.archived, false) or x.${b("archivedAt")} is null)
$$;
${userGrant(`${fn("list_post_boards")}(${ctx.idType}, boolean)`)}
`;
}

function postWrites(ctx: ModuleContext): string {
  const q = postsSql(ctx);

  const { fn, b, p, boards, posts, subject, invalid, forbidden, postMissing } =
    q;

  const track = q.moderation.fn("moderation_track");
  const banned = q.moderation.fn("moderation_banned");
  const initial = q.mode === "pre" ? "'pending'" : "'visible'";

  const json = (row: string): string =>
    `${q.postJson(row)} || jsonb_build_object('votes', ${q.reactions.fn("vote_tally")}(${row}.${p("tenant")}, ${subject}, ${row}.${p("id")}::text))`;

  const moderator = (row: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", `${row}.${p("tenant")}`, q.moderate)})`;

  const load = (
    func: string,
    arg: string,
  ): string => `select * into v_row from ${posts} x where x.${p("id")} = ${func}.${arg} for update;
  if not found then
    ${postMissing}
  end if;`;

  return `-- A post the caller writes on a board: post is { title, body, fields }. It is
-- published at once, or held for a moderator when options.moderation is
-- "pre". Banned members can't post.
create or replace function ${fn("create_post")}(board_id uuid, post jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_me uuid := auth.uid();
  v_board ${boards};
  v_row ${posts};
  v_title text := trim(create_post.post ->> 'title');
  v_body text := coalesce(create_post.post ->> 'body', '');
begin
  select * into v_board from ${boards} x where x.${b("id")} = create_post.board_id;
  if not found then
    ${q.boardMissing}
  end if;
  if not ${q.allowed(`v_board.${b("tenant")}`, q.write)} or (v_me is null and not (${SERVICE_CALLER})) then
    ${forbidden("not allowed to post on this board")}
  end if;
  if v_board.${b("archivedAt")} is not null then
    ${invalid("the board is archived")}
  end if;
  if ${banned}(v_board.${b("tenant")}, v_me) then
    ${forbidden("you are banned from posting in this organization")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${invalid("a post needs a title of 1 to 300 characters")}
  end if;
  if length(v_body) > ${String(q.maxBody)} then
    ${invalid(`a post's body is at most ${String(q.maxBody)} characters`)}
  end if;
  insert into ${posts} (${p("tenant")}, ${p("board")}, ${p("author")}, ${p("title")}, ${p("body")}, ${p("moderation")})
  values (v_board.${b("tenant")}, v_board.${b("id")}, v_me, v_title, v_body, ${initial})
  returning * into v_row;${writeExtraColumns(posts, q.extras, "(create_post.post -> 'fields')", `x.${p("id")} = v_row.${p("id")}`, "v_row")}
  perform ${track}(v_row.${p("tenant")}, ${subject}, v_row.${p("id")}::text, v_me, ${initial});
  ${q.record("post.created", "v_row", false)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("create_post")}(uuid, jsonb)`)}

-- Changes a post's title, body or fields: its author while it isn't locked, or a
-- moderator. Under pre-moderation the author's edit goes back to the queue.
create or replace function ${fn("update_post")}(post_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${posts};
  v_moderator boolean;
  v_title text;
  v_body text;
begin
  ${load("update_post", "post_id")}
  v_moderator := ${moderator("v_row")};
  if not v_moderator and (v_row.${p("author")} is distinct from auth.uid() or v_row.${p("lockedAt")} is not null) then
    ${forbidden("not allowed to change this post")}
  end if;
  if jsonb_typeof(update_post.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  v_title := case when update_post.attrs ? 'title' then trim(update_post.attrs ->> 'title') else v_row.${p("title")} end;
  v_body := case when update_post.attrs ? 'body' then coalesce(update_post.attrs ->> 'body', '') else v_row.${p("body")} end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${invalid("a post needs a title of 1 to 300 characters")}
  end if;
  if length(v_body) > ${String(q.maxBody)} then
    ${invalid(`a post's body is at most ${String(q.maxBody)} characters`)}
  end if;
  update ${posts} x set ${p("title")} = v_title, ${p("body")} = v_body, ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;${writeExtraColumns(posts, q.extras, "(update_post.attrs -> 'fields')", `x.${p("id")} = v_row.${p("id")}`, "v_row")}${
    q.mode === "pre"
      ? `
  if not v_moderator then
    perform ${track}(v_row.${p("tenant")}, ${subject}, v_row.${p("id")}::text, v_row.${p("author")}, 'pending');
    select * into v_row from ${posts} x where x.${p("id")} = v_row.${p("id")};
  end if;`
      : ""
  }
  ${q.record("post.updated", "v_row", false)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("update_post")}(uuid, jsonb)`)}

-- Sets a post's status (open, under_review, planned, in_progress, done or
-- closed), pins or unpins it and locks or unlocks its replies. attrs is
-- { status?, pinned?, locked? }. Moderators only.
create or replace function ${fn("set_post_state")}(post_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${posts};
  v_old ${posts};
begin
  ${load("set_post_state", "post_id")}
  if not ${moderator("v_row")} then
    ${forbidden("not allowed to moderate posts")}
  end if;
  if jsonb_typeof(set_post_state.attrs) is distinct from 'object' then
    ${invalid("attrs must be an object")}
  end if;
  v_old := v_row;
  update ${posts} x set
    ${p("status")} = coalesce(set_post_state.attrs ->> 'status', x.${p("status")}),
    ${p("pinnedAt")} = case when set_post_state.attrs ? 'pinned' then case when (set_post_state.attrs ->> 'pinned')::boolean then coalesce(x.${p("pinnedAt")}, now()) end else x.${p("pinnedAt")} end,
    ${p("lockedAt")} = case when set_post_state.attrs ? 'locked' then case when (set_post_state.attrs ->> 'locked')::boolean then coalesce(x.${p("lockedAt")}, now()) end else x.${p("lockedAt")} end,
    ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  if v_row.${p("status")} is distinct from v_old.${p("status")} then
    ${q.record("post.status_changed", "v_row", "changed a post's status")}
  elsif v_row.${p("pinnedAt")} is distinct from v_old.${p("pinnedAt")} or v_row.${p("lockedAt")} is distinct from v_old.${p("lockedAt")} then
    ${q.record("post.updated", "v_row", "pinned or locked a post")}
  end if;
  return ${json("v_row")};
exception when check_violation then
  ${invalid("unknown post status")}
end;
$$;
${userGrant(`${fn("set_post_state")}(uuid, jsonb)`)}

-- Merges a duplicate into another post on the same board: the duplicate
-- closes and points at the other, and its votes move there unless the voter
-- already voted on it. Replies stay on the duplicate. Moderators only.
create or replace function ${fn("merge_posts")}(source_id uuid, target_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${posts};
  v_target ${posts};
begin
  ${load("merge_posts", "source_id")}
  select * into v_target from ${posts} x where x.${p("id")} = merge_posts.target_id for update;
  if not found or v_target.${p("board")} is distinct from v_row.${p("board")} then
    ${postMissing}
  end if;
  if not ${moderator("v_row")} then
    ${forbidden("not allowed to moderate posts")}
  end if;
  if v_target.${p("id")} = v_row.${p("id")} or v_target.${p("mergedInto")} is not null then
    ${invalid("merge into another post that wasn't merged itself")}
  end if;
  ${mergeVotes(ctx, "v_row", "v_target")}
  update ${posts} x set ${p("mergedInto")} = v_target.${p("id")}, ${p("status")} = 'closed', ${p("updatedAt")} = now()
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  update ${posts} x set ${p("mergedInto")} = v_target.${p("id")}, ${p("updatedAt")} = now()
  where x.${p("mergedInto")} = v_row.${p("id")};
  ${q.record("post.merged", "v_row", "merged a post")}
  return ${json("v_target")};
end;
$$;
${userGrant(`${fn("merge_posts")}(uuid, uuid)`)}

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function ${fn("delete_post")}(post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${posts};
begin
  select * into v_row from ${posts} x where x.${p("id")} = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not (${moderator("v_row")} or coalesce(v_row.${p("author")} = auth.uid(), false)) then
    ${forbidden("not allowed to delete this post")}
  end if;
  delete from ${posts} x where x.${p("id")} = v_row.${p("id")};
  ${q.record("post.deleted", "v_row", "deleted a post")}
  return true;
end;
$$;
${userGrant(`${fn("delete_post")}(uuid)`)}
`;
}

/** Moves the duplicate's votes to the target, skipping voters who voted there. */
function mergeVotes(
  ctx: ModuleContext,
  source: string,
  target: string,
): string {
  const q = postsSql(ctx);
  const { p, subject, reactions } = q;
  const c = (column: string): string => reactions.col("reactions", column);
  const table = reactions.table("reactions");

  return `insert into ${table} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("actor")}, ${c("user")}, ${c("kind")}, ${c("emoji")}, ${c("value")})
  select r.${c("tenant")}, r.${c("subjectType")}, ${target}.${p("id")}::text, r.${c("actor")}, r.${c("user")}, r.${c("kind")}, r.${c("emoji")}, r.${c("value")}
  from ${table} r
  where r.${c("tenant")} = ${source}.${p("tenant")} and r.${c("subjectType")} = ${subject}
    and r.${c("subjectId")} = ${source}.${p("id")}::text and r.${c("kind")} = 'vote'
    and not exists (
      select 1 from ${table} t
      where t.${c("tenant")} = r.${c("tenant")} and t.${c("subjectType")} = ${subject}
        and t.${c("subjectId")} = ${target}.${p("id")}::text and t.${c("kind")} = 'vote' and t.${c("actor")} = r.${c("actor")}
    );
  delete from ${table} r
  where r.${c("tenant")} = ${source}.${p("tenant")} and r.${c("subjectType")} = ${subject}
    and r.${c("subjectId")} = ${source}.${p("id")}::text and r.${c("kind")} = 'vote';`;
}

function postReads(ctx: ModuleContext): string {
  const q = postsSql(ctx);

  const { fn, p, posts, subject, reactions, invalid, forbidden, postMissing } =
    q;

  const sc = (column: string): string => reactions.col("scores", column);
  const rc = (column: string): string => reactions.col("reactions", column);

  const votes = (row: string, score: string): string =>
    `jsonb_build_object('votes', jsonb_build_object('score', coalesce(${score}.${sc("score")}, 0), 'up', coalesce(${score}.${sc("up")}, 0), 'down', coalesce(${score}.${sc("down")}, 0), 'vote', coalesce((
      select r.${rc("value")} from ${reactions.table("reactions")} r
      where r.${rc("tenant")} = ${row}.${p("tenant")} and r.${rc("subjectType")} = ${subject}
        and r.${rc("subjectId")} = ${row}.${p("id")}::text and r.${rc("kind")} = 'vote'
        and r.${rc("user")} = (select auth.uid())
    ), 0)))`;

  const scoreJoin = (row: string): string =>
    `left join ${reactions.table("scores")} s on s.${sc("tenant")} = ${row}.${p("tenant")} and s.${sc("subjectType")} = ${subject} and s.${sc("subjectId")} = ${row}.${p("id")}::text`;

  return `-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function ${fn("get_post")}(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${q.postJson("x")} || ${votes("x", "s")}
  from ${posts} x
  ${scoreJoin("x")}
  where x.${p("id")} = get_post.post_id
$$;
${userGrant(`${fn("get_post")}(uuid)`)}

-- Posts the caller reads. filter is { boardId?, status?, authorId?, sort?,
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
create or replace function ${fn("list_posts")}(tenant ${ctx.idType}, filter jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_posts.filter, '{}'::jsonb);
  v_sort text := coalesce(v_filter ->> 'sort', 'active');
begin
  if v_sort not in ('active', 'new', 'top') then
    ${invalid("sort is active, new or top")}
  end if;
  return (
    select coalesce(jsonb_agg(e.row order by e.n), '[]'::jsonb)
    from (
      select ${q.postJson("x")} || ${votes("x", "s")} as row,
        row_number() over (order by
          case when v_sort = 'active' then x.${p("pinnedAt")} end desc nulls last,
          case when v_sort = 'top' then coalesce(s.${sc("score")}, 0) end desc,
          case when v_sort = 'active' then x.${p("lastActivityAt")} end desc,
          x.${p("createdAt")} desc, x.${p("id")}) as n
      from ${posts} x
      ${scoreJoin("x")}
      where x.${p("tenant")} = list_posts.tenant
        and (v_filter ->> 'boardId' is null or x.${p("board")} = (v_filter ->> 'boardId')::uuid)
        and (v_filter ->> 'status' is null or x.${p("status")} = v_filter ->> 'status')
        and (v_filter ->> 'authorId' is null or x.${p("author")} = (v_filter ->> 'authorId')::uuid)
        and (coalesce((v_filter ->> 'merged')::boolean, false) or x.${p("mergedInto")} is null)
      order by n
      limit ${pageSize("(v_filter ->> 'limit')::integer", 50, 200)}
      offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
    ) e
  );
end;
$$;
${userGrant(`${fn("list_posts")}(${ctx.idType}, jsonb)`)}

-- Sets the caller's vote on a post they read: 1 up, -1 down, 0 clears it.
-- Returns the post's tally. A merged post takes no votes.
create or replace function ${fn("vote_on_post")}(post_id uuid, value integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${ctx.idType};
  v_merged uuid;
begin
  select x.${p("tenant")}, x.${p("mergedInto")} into v_tenant, v_merged
  from ${posts} x where x.${p("id")} = vote_on_post.post_id and x.${p("moderation")} = 'visible';
  if not found then
    ${postMissing}
  end if;
  if v_merged is not null then
    ${forbidden("the post was merged; vote on the post it was merged into")}
  end if;
  return ${reactions.fn("vote")}(v_tenant, ${subject}, vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
${userGrant(`${fn("vote_on_post")}(uuid, integer)`)}
`;
}

/** The posts module's functions. */
export function postFunctions(ctx: ModuleContext): string {
  return `${boardFunctions(ctx)}${postWrites(ctx)}${postReads(ctx)}`;
}
