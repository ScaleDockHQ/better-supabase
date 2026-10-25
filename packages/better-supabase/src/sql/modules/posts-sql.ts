import type { ExtraColumn, BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, withExtraFields } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const WHERE = "blocks.posts.options";

/** The keys post reads return next to the extra columns. */
const POST_KEYS = [
  "id",
  "organizationId",
  "boardId",
  "authorId",
  "mine",
  "title",
  "body",
  "status",
  "moderation",
  "pinnedAt",
  "lockedAt",
  "mergedIntoId",
  "replyCount",
  "lastActivityAt",
  "createdAt",
  "updatedAt",
  "votes",
  "fields",
] as const;

/** The SQL pieces the posts files share. */
export interface PostsSql {
  readonly fn: (name: string) => string;
  /** A column of the boards table. */
  readonly b: (column: string) => string;
  /** A column of the posts table. */
  readonly p: (column: string) => string;
  /** Whether the boards table has an optional column. */
  readonly hasBoard: (column: string) => boolean;
  /** Whether the posts table has an optional column. */
  readonly hasPost: (column: string) => boolean;
  readonly boards: string;
  readonly posts: string;
  /** The posts' subject type, after renames, as a SQL literal. */
  readonly subject: string;
  readonly moderation: BlockSqlContext;
  readonly reactions: BlockSqlContext;
  readonly messaging: BlockSqlContext;
  /** "post" publishes a new post at once; "pre" holds it for a moderator. */
  readonly mode: "pre" | "post";
  readonly maxBody: number;
  /** The posts table's extra columns (`options.extraColumns`). */
  readonly extras: readonly ExtraColumn[];
  readonly read: string;
  readonly write: string;
  readonly moderate: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly postMissing: string;
  readonly boardMissing: string;
  readonly boardJson: (row: string) => string;
  readonly postJson: (row: string) => string;
  /**
   * Records a `post.*` event of a posts row; `false` leaves it out of the audit
   * log.
   */
  readonly record: (
    type: string,
    row: string,
    summary: string | false,
  ) => string;
}

function modeOf(ctx: BlockSqlContext): "pre" | "post" {
  const mode = ctx.text("moderation", "post");

  if (mode !== "pre" && mode !== "post") {
    throw new TypeError(`${WHERE}.moderation must be "pre" or "post"`);
  }

  return mode;
}

function maxBodyOf(ctx: BlockSqlContext): number {
  const max = ctx.number("maxBodyLength", 20_000);

  if (!Number.isInteger(max) || max < 1 || max > 200_000) {
    throw new TypeError(
      `${WHERE}.maxBodyLength must be an integer from 1 to 200000`,
    );
  }

  return max;
}

export function postsSql(ctx: BlockSqlContext): PostsSql {
  const keys = moduleOperations("posts");
  const b = (column: string): string => ctx.col("boards", column);
  const p = (column: string): string => ctx.col("posts", column);
  const hasBoard = (column: string): boolean => ctx.has("boards", column);
  const hasPost = (column: string): boolean => ctx.has("posts", column);
  const extras = ctx.extraColumns("posts", POST_KEYS);

  // Column `column` of row `row`, or `missing` when the app's table lacks it.
  const board = (row: string, column: string, missing = "null"): string =>
    hasBoard(column) ? `${row}.${b(column)}` : missing;

  const post = (row: string, column: string, missing = "null"): string =>
    hasPost(column) ? `${row}.${p(column)}` : missing;

  return {
    fn: (name) => ctx.fn(name),
    b,
    p,
    hasBoard,
    hasPost,
    boards: ctx.table("boards"),
    posts: ctx.table("posts"),
    subject: sqlString(ctx.naming.rename("post")),
    moderation: ctx.of("moderation"),
    reactions: ctx.of("reactions"),
    messaging: ctx.of("messaging"),
    mode: modeOf(ctx),
    maxBody: maxBodyOf(ctx),
    extras,
    read: ctx.permission("read", keys.read),
    write: ctx.permission("write", keys.write),
    moderate: ctx.permission("moderate", keys.moderate),
    manage: ctx.permission("manage", keys.manage),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("POST_INVALID", message, "22023"),
    forbidden: (message) => fail("POST_FORBIDDEN", message),
    postMissing: fail("POST_NOT_FOUND", "no such post", "P0002"),
    boardMissing: fail("POST_BOARD_NOT_FOUND", "no such board", "P0002"),
    boardJson: (row) =>
      `jsonb_build_object('id', ${row}.${b("id")}, 'organizationId', ${row}.${b("tenant")}, 'key', ${row}.${b("key")}, 'name', ${row}.${b("name")}, 'description', ${board(row, "description")}, 'kind', ${row}.${b("kind")}, 'archivedAt', ${board(row, "archivedAt")}, 'createdBy', ${board(row, "createdBy")}, 'createdAt', ${row}.${b("createdAt")}, 'updatedAt', ${board(row, "updatedAt", `${row}.${b("createdAt")}`)})`,
    postJson: (row) =>
      withExtraFields(
        `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'boardId', ${row}.${p("board")}, 'authorId', ${row}.${p("author")}, 'mine', coalesce(${row}.${p("author")} = (select auth.uid()), false), 'title', ${row}.${p("title")}, 'body', ${row}.${p("body")}, 'status', ${row}.${p("status")}, 'moderation', ${row}.${p("moderation")}, 'pinnedAt', ${post(row, "pinnedAt")}, 'lockedAt', ${post(row, "lockedAt")}, 'mergedIntoId', ${row}.${p("mergedInto")}, 'replyCount', ${post(row, "replyCount", "0")}, 'lastActivityAt', ${post(row, "lastActivityAt", `${row}.${p("createdAt")}`)}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${post(row, "updatedAt", `${row}.${p("createdAt")}`)})`,
        row,
        extras,
      ),
    record: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'boardId', ${row}.${p("board")}, 'authorId', ${row}.${p("author")}, 'status', ${row}.${p("status")}, 'moderation', ${row}.${p("moderation")}, 'mergedIntoId', ${row}.${p("mergedInto")})`,
        subject: `'posts/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit:
          summary === false
            ? false
            : {
                category: "data",
                targetType: "post",
                recordId: `${row}.${p("id")}::text`,
                targetLabel: `${row}.${p("title")}`,
                summary: sqlString(summary),
              },
      }),
  };
}
