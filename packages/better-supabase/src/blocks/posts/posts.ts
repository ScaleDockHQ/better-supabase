import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

const BOARD_KINDS = ["forum", "feedback"] as const;

const POST_STATUSES = [
  "open",
  "under_review",
  "planned",
  "in_progress",
  "done",
  "closed",
] as const;

const MODERATION = ["visible", "pending", "hidden", "removed"] as const;

/**
 * A forum board holds discussions; a feedback board holds ideas members vote
 * on.
 */
export type PostBoardKind = (typeof BOARD_KINDS)[number];

/** Where a post stands, from a feedback board's point of view. */
export type PostStatus = (typeof POST_STATUSES)[number];

/** The post's moderation item status. Only visible posts show to everyone. */
export type PostModeration = (typeof MODERATION)[number];

export interface PostBoard {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly kind: PostBoardKind;
  readonly archivedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface PostBoardInput {
  /** Leave out to create a board. */
  readonly id?: string;
  /** Lowercase letters, digits, dashes and underscores; fixed once created. */
  readonly key?: string;
  readonly name?: string;
  readonly description?: string | null;
  readonly kind?: PostBoardKind;
  readonly archived?: boolean;
}

export interface PostVotes {
  /** Up votes minus down votes. */
  readonly score: number;
  readonly up: number;
  readonly down: number;
  /** The caller's vote: 1, -1 or 0. */
  readonly vote: number;
}

/** A post. `F` types the extra columns the `fields` schema describes. */
export interface Post<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly boardId: string;
  readonly authorId?: string;
  /** True when the caller wrote it. */
  readonly mine: boolean;
  readonly title: string;
  readonly body: string;
  readonly status: PostStatus;
  readonly moderation: PostModeration;
  readonly pinnedAt?: Temporal.Instant;
  readonly lockedAt?: Temporal.Instant;
  /** The post this one was merged into as a duplicate. */
  readonly mergedIntoId?: string;
  readonly replyCount: number;
  readonly lastActivityAt: Temporal.Instant;
  readonly votes: PostVotes;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface PostInput<F extends object = Record<never, never>> {
  readonly title: string;
  readonly body?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** What `setState` changes; moderators only. */
export interface PostStateInput {
  readonly status?: PostStatus;
  readonly pinned?: boolean;
  readonly locked?: boolean;
}

export interface PostsFilter {
  readonly boardId?: string;
  readonly status?: PostStatus;
  readonly authorId?: string;
  /** Active (pinned, then latest activity; the default), new or top. */
  readonly sort?: "active" | "new" | "top";
  /** Include posts merged into others. */
  readonly merged?: boolean;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface Posts<F extends object = Record<never, never>> {
  /** Creates or changes a board; needs `posts.manage`. */
  saveBoard(input: PostBoardInput): AsyncResult<PostBoard>;
  boards(filter?: {
    readonly archived?: boolean;
  }): AsyncResult<readonly PostBoard[]>;
  /**
   * Writes a post on a board. It shows at once, or waits for a moderator when
   * `options.moderation` is "pre". Banned members can't post.
   */
  create(input: { boardId: string; input: PostInput<F> }): AsyncResult<Post<F>>;
  /** Changes the caller's own post, or any post for a moderator. */
  update(input: {
    postId: string;
    input: Partial<PostInput<F>>;
  }): AsyncResult<Post<F>>;
  /** Deletes a post; false when there was none. */
  delete(postId: string): AsyncResult<boolean>;
  get(postId: string): AsyncResult<Post<F> | null>;
  list(filter?: PostsFilter): AsyncResult<readonly Post<F>[]>;
  /** Sets the status, pin or lock of a post; needs `posts.moderate`. */
  setState(input: {
    postId: string;
    input: PostStateInput;
  }): AsyncResult<Post<F>>;
  /** 1 up, -1 down, 0 clears the caller's vote. Returns the tally. */
  vote(input: { postId: string; value: -1 | 0 | 1 }): AsyncResult<PostVotes>;
  /** Closes a duplicate and moves its votes to `targetId`. Returns the target. */
  merge(input: { sourceId: string; targetId: string }): AsyncResult<Post<F>>;
}

export interface PostsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the post's extra columns
   * (`blocks.posts.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Posts<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

function boardOf(value: unknown, fn: string): PostBoard {
  const row = recordOf(value, fn);
  const description = optionalText(row["description"]);
  const createdBy = optionalText(row["createdBy"]);
  const archivedAt = optionalInstant(row["archivedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    kind: enumOrThrow(row["kind"], BOARD_KINDS, "board kind"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...(description === undefined ? {} : { description }),
    ...(createdBy === undefined ? {} : { createdBy }),
    ...(archivedAt === undefined ? {} : { archivedAt }),
  };
}

function tallyOf(value: unknown): PostVotes {
  const row = isRecord(value) ? value : {};
  const count = (key: string): number => Number(row[key] ?? 0);

  return {
    score: count("score"),
    up: count("up"),
    down: count("down"),
    vote: count("vote"),
  };
}

function postOf(value: unknown, fn: string): Post {
  const row = recordOf(value, fn);
  const authorId = optionalText(row["authorId"]);
  const mergedIntoId = optionalText(row["mergedIntoId"]);
  const pinnedAt = optionalInstant(row["pinnedAt"]);
  const lockedAt = optionalInstant(row["lockedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    boardId: textOf(row["boardId"]),
    mine: row["mine"] === true,
    title: textOf(row["title"]),
    body: typeof row["body"] === "string" ? row["body"] : "",
    status: enumOrThrow(row["status"], POST_STATUSES, "post status"),
    moderation: enumOrThrow(row["moderation"], MODERATION, "post moderation"),
    replyCount: Number(row["replyCount"] ?? 0),
    lastActivityAt: requiredInstant(row["lastActivityAt"], "lastActivityAt"),
    votes: tallyOf(row["votes"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...(authorId === undefined ? {} : { authorId }),
    ...(mergedIntoId === undefined ? {} : { mergedIntoId }),
    ...(pinnedAt === undefined ? {} : { pinnedAt }),
    ...(lockedAt === undefined ? {} : { lockedAt }),
  };
}

/**
 * Forum and feedback posts on boards. Replies are comments on the post's
 * subject, votes are reactions, and each post is a moderation item.
 */
export function createPosts<S extends StandardSchemaV1 | undefined = undefined>(
  options: PostsOptions<S>,
): Posts<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "post fields");
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const post = (fn: string) => (value: unknown) => postOf(value, fn);

  const write = (input: Partial<PostInput<F>>) => {
    const { fields: extra, ...rest } = input;

    return fields
      .args(extra)
      .map((checked) => ({
        ...definedOf(rest),
        ...(checked === undefined ? {} : { fields: checked }),
      }));
  };

  const client: Posts<F> = {
    saveBoard: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_post_board",
          { tenant: organizationId, board: definedOf(input) },
          (value) => boardOf(value, "save_post_board"),
        ),
      ),
    boards: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_post_boards",
          { tenant: organizationId, archived: filter.archived ?? false },
          (value) =>
            recordsOf(value, "list_post_boards").map((row) =>
              boardOf(row, "list_post_boards"),
            ),
        ),
      ),
    create: ({ boardId, input }) =>
      write(input).andThen((attrs) =>
        call(
          "create_post",
          { board_id: boardId, post: attrs },
          post("create_post"),
        ).andThen(fields.row),
      ),
    update: ({ postId, input }) =>
      write(input).andThen((attrs) =>
        call(
          "update_post",
          { post_id: postId, attrs },
          post("update_post"),
        ).andThen(fields.row),
      ),
    delete: (postId) =>
      call("delete_post", { post_id: postId }, (value) => value === true),
    get: (postId) =>
      call("get_post", { post_id: postId }, (value) =>
        value === null || value === undefined
          ? null
          : postOf(value, "get_post"),
      ).andThen((row) =>
        row === null ? AsyncResult.ok(null) : fields.row(row),
      ),
    list: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_posts",
          { tenant: organizationId, filter: definedOf(filter) },
          (value) => recordsOf(value, "list_posts").map(post("list_posts")),
        ).andThen(fields.rows),
      ),
    setState: ({ postId, input }) =>
      call(
        "set_post_state",
        { post_id: postId, attrs: definedOf(input) },
        post("set_post_state"),
      ).andThen(fields.row),
    vote: ({ postId, value }) =>
      call("vote_on_post", { post_id: postId, value }, tallyOf),
    merge: ({ sourceId, targetId }) =>
      call(
        "merge_posts",
        { source_id: sourceId, target_id: targetId },
        post("merge_posts"),
      ).andThen(fields.row),
  };

  return withBlockHooks(client, options.hooks, {
    block: "posts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
