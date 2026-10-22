import type { PostsEvents } from "../../blocks/posts/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { postFunctions } from "./posts-functions.ts";
import { postsSql } from "./posts-sql.ts";
import { POST_TRIGGERS, postTriggers } from "./posts-triggers.ts";

const POST_PAYLOAD = [
  "organizationId",
  "id",
  "boardId",
  "authorId",
  "status",
  "moderation",
  "mergedIntoId",
] as const;

const post = { subject: "posts", payload: POST_PAYLOAD } as const;

const EVENTS: ModuleEvents<PostsEvents> = {
  "post_board.saved": {
    subject: "post-boards",
    payload: ["organizationId", "id", "key", "kind"],
  },
  "post.created": post,
  "post.updated": post,
  "post.status_changed": post,
  "post.moderated": post,
  "post.merged": post,
  "post.deleted": post,
};

const NAMES: ModuleNames = {
  entities: {
    post_board: { table: "boards", singular: "post_board" },
    post: {
      table: "posts",
      singular: "post",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["body"] },
      },
    },
  },
  events: EVENTS,
  options: ["moderation", "maxBodyLength", "extraColumns"],
  tables: {
    boards: {
      name: "post_boards",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        description: "description",
        kind: "kind",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    posts: {
      name: "posts",
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        board: "board_id",
        author: "author_id",
        title: "title",
        body: "body",
        status: "status",
        moderation: "moderation_status",
        pinnedAt: "pinned_at",
        lockedAt: "locked_at",
        mergedInto: "merged_into_id",
        replyCount: "reply_count",
        lastActivityAt: "last_activity_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

/** The statuses a post moves through, from a feedback board's point of view. */
export const POST_STATUSES = [
  "open",
  "under_review",
  "planned",
  "in_progress",
  "done",
  "closed",
] as const;

function tables(ctx: ModuleContext): string {
  const q = postsSql(ctx);
  const { b, p, boards, posts, read, moderate } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const statuses = POST_STATUSES.map((status) => `'${status}'`).join(", ");

  return `create table if not exists ${boards} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${ctx.idType} not null,
  ${b("key")} text not null check (${b("key")} ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  ${b("name")} text not null check (length(${b("name")}) between 1 and 200),
  ${b("description")} text check (${b("description")} is null or length(${b("description")}) <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  ${b("kind")} text not null default 'forum' check (${b("kind")} in ('forum', 'feedback')),
  ${b("archivedAt")} timestamptz,
  ${b("createdBy")} uuid,
  ${b("createdAt")} timestamptz not null default now(),
  ${b("updatedAt")} timestamptz not null default now(),
  unique (${b("tenant")}, ${b("key")})
);

create table if not exists ${posts} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("board")} uuid not null references ${boards} (${b("id")}) on delete cascade,
  ${p("author")} uuid references auth.users (id) on delete set null,
  ${p("title")} text not null check (length(${p("title")}) between 1 and 300),
  ${p("body")} text not null default '' check (length(${p("body")}) <= ${String(q.maxBody)}),
  ${p("status")} text not null default 'open' check (${p("status")} in (${statuses})),
  -- The moderation item's status, kept in step by a trigger.
  ${p("moderation")} text not null default 'visible' check (${p("moderation")} in ('visible', 'pending', 'hidden', 'removed')),
  ${p("pinnedAt")} timestamptz,
  ${p("lockedAt")} timestamptz,
  ${p("mergedInto")} uuid references ${posts} (${p("id")}) on delete set null check (${p("mergedInto")} is distinct from ${p("id")}),
  ${p("replyCount")} integer not null default 0,
  ${p("lastActivityAt")} timestamptz not null default now(),
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now()
);${addExtraColumns(posts, q.extras)}
create index if not exists ${name("posts", "board_idx")} on ${posts} (${p("board")}, ${p("pinnedAt")} desc nulls last, ${p("lastActivityAt")} desc);
create index if not exists ${name("posts", "tenant_idx")} on ${posts} (${p("tenant")}, ${p("createdAt")} desc);
create index if not exists ${name("posts", "author_idx")} on ${posts} (${p("author")});
create index if not exists ${name("posts", "merged_idx")} on ${posts} (${p("mergedInto")});

${lockTable(boards, { read: true })}
drop policy if exists ${name("boards", "read")} on ${boards};
create policy ${name("boards", "read")} on ${boards} for select to authenticated
  using (${ctx.scope.check(b("tenant"), read)});
${lockTable(posts, { read: true })}
drop policy if exists ${name("posts", "read")} on ${posts};
create policy ${name("posts", "read")} on ${posts} for select to authenticated
  using (${ctx.scope.check(p("tenant"), read)} and (
    ${p("moderation")} = 'visible'
    or ${p("author")} = (select auth.uid())
    or ${ctx.scope.check(p("tenant"), moderate)}
  ));
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  for (const module of ["messaging", "comments", "reactions", "moderation"]) {
    if (ctx.of(module).mode === "custom") {
      throw new TypeError(`posts needs the ${module} module's tables`);
    }
  }

  return `${schemaPreamble(ctx)}
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
${tables(ctx)}
${postFunctions(ctx)}
${postTriggers(ctx)}`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "save_post_board", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "list_post_boards", args: ["{id}", "boolean"], returns: "jsonb" },
    { name: "create_post", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "update_post", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "get_post", args: ["uuid"], returns: "jsonb" },
    { name: "list_posts", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "set_post_state", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "vote_on_post", args: ["uuid", "integer"], returns: "jsonb" },
    { name: "merge_posts", args: ["uuid", "uuid"], returns: "jsonb" },
    { name: "delete_post", args: ["uuid"], returns: "boolean" },
  ];
}

export const POSTS: ModuleDefinition = {
  internal: [...POST_TRIGGERS],
  name: "posts",
  scopes: ["tenant"],
  title: "Posts",
  description:
    "Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.",
  requires: [
    "tenant",
    "access",
    "subjects",
    "messaging",
    "comments",
    "reactions",
    "moderation",
  ],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
