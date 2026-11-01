import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type {
  Message,
  MessageEdit,
  MessageEdition,
} from "../messaging/messaging.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { bySubjectType, subjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { parseMentions } from "../messaging/mentions.ts";
import { editOf, messageOf } from "../messaging/rows.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  requiredInstant,
} from "../shared.ts";

export interface CommentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockTemporalOptions, BlockTenantOptions {
  /**
   * A Standard Schema for the message extra columns
   * (`blocks.messaging.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `create` and `edit`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Comments<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * The user ids (or mention groups) a comment mentions when the call passes no
   * `mentionIds`, such as the mention nodes of a rich-text `document`. Default
   * `mentionsIn(body)`.
   */
  readonly mentionsOf?: (comment: {
    readonly body: string;
    readonly document: unknown;
  }) => readonly string[];
}

/**
 * A comment: a message in its record's conversation. `F` types the extra
 * columns the `fields` schema describes.
 */
export interface Comment<
  F extends object = Record<never, never>,
> extends Message<F> {
  /** The record the comment is on. */
  readonly subject: RecordRef;
  /** The work item `assign` turned it into, with the `tasks` block. */
  readonly taskId: string | undefined;
}

export interface NewComment<F extends object = Record<never, never>> {
  /** Plain text; `@[Name](<user id>)` mentions a user. */
  readonly body: string;
  /** A rich-text document (any JSON); keep `body` as its plain text. */
  readonly document?: unknown;
  /**
   * Where on the record the comment points, such as a text range or a field
   * (any JSON), or a page, region or moment of a file (`fileAnchor`). Top-level
   * comments only.
   */
  readonly anchor?: unknown;
  /**
   * User ids or mention groups (`options.mentionGroups`); default `mentionsOf`,
   * or the ids `mentionsIn(body)` finds.
   */
  readonly mentionIds?: readonly string[];
  /** A reply: with one level of threads, a reply to a reply joins the root. */
  readonly parentId?: string;
  /** Files the caller uploaded to the record's conversation (`attachments`). */
  readonly attachmentIds?: readonly string[];
  /** The extra columns to set, keyed by database name. */
  readonly fields?: Partial<F>;
}

/** What `edit` takes. */
export type CommentEdit<F extends object = Record<never, never>> =
  MessageEdition<F>;

/** What `assign` passes to the work item. */
export interface CommentAssignment {
  /** Who works on it; nobody when left out. */
  readonly assigneeId?: string;
  /** Default the comment's first 120 characters. */
  readonly title?: string;
  /** Default the comment's body. */
  readonly body?: string;
  /** Other `create_task` attributes, such as `projectId` or `priority`. */
  readonly attrs?: Readonly<Record<string, unknown>>;
}

export interface ListCommentsOptions extends CursorPageOptions<Temporal.Instant> {
  /** Comments sent after this instant, for polling a thread. */
  readonly cursor?: Temporal.Instant;
  /**
   * The id of the last comment you have, next to `cursor`, so comments sent in
   * the same instant as it aren't skipped.
   */
  readonly cursorId?: string;
  /** Default 100, at most 500. */
  readonly limit?: number;
  /** Comments to skip, for page-number paging. */
  readonly offset?: number;
  /**
   * Default `true`: deleted comments stay in the list as placeholders, so
   * replies keep their parent. `false` leaves them out, as `counts` does.
   */
  readonly includeDeleted?: boolean;
}

/**
 * `F` is the extra fields `options.fields` describes. Every method that takes a
 * record acts in the block's `tenant`.
 */
export interface Comments<F extends object = Record<never, never>> {
  /** Posts a comment on `subject`, opening its conversation the first time. */
  create(input: {
    subject: RecordRef;
    comment: NewComment<F>;
  }): AsyncResult<Comment<F>>;
  /** One comment, or `not_found` when the caller can't read it. */
  get(id: string): AsyncResult<Comment<F>>;
  /** The top-level comments anchored to a file (`fileAnchor`), oldest first. */
  anchoredTo(
    input: { attachmentId: string } & { readonly limit?: number },
  ): AsyncResult<Comment<F>[]>;
  /** The author edits within `editWindow`; the old version is kept. */
  edit(input: { id: string; edit: CommentEdit<F> }): AsyncResult<Comment<F>>;
  /** Soft-deletes (the author, or a member with `comments.moderate`). */
  remove(id: string): AsyncResult<boolean>;
  /** Resolves a thread by its root comment, or opens it again. */
  resolve(input: {
    id: string;
    resolved?: boolean | undefined;
  }): AsyncResult<Comment<F>>;
  /** Pins a comment to the top of its record, or unpins it. */
  pin(input: {
    id: string;
    pinned?: boolean | undefined;
  }): AsyncResult<Comment<F>>;
  /** The earlier versions of an edited comment, newest first. */
  edits(id: string): AsyncResult<readonly MessageEdit[]>;
  /**
   * Turns a comment into a work item (with the `tasks` block) and returns its
   * id; assigning it again returns the same one.
   */
  assign(input: {
    id: string;
    assignment?: CommentAssignment | undefined;
  }): AsyncResult<string>;
  /**
   * A record's comments and replies, oldest first, deleted ones as
   * placeholders.
   */
  list(
    input: { subject: RecordRef } & ListCommentsOptions,
  ): AsyncResult<readonly Comment<F>[]>;
  /**
   * How many comments each subject has that the caller can read, deleted ones
   * left out, such as for a counter on each row of a list, keyed by
   * `subjectKey(subject)` (`type:id`). Subjects without comments are 0.
   */
  counts(
    subjects: readonly RecordRef[],
  ): AsyncResult<Readonly<Record<string, number>>>;
  /**
   * Copies a subject's thread to another subject in the tenant, keeping
   * authors, times and replies; returns how many comments it copied. Needs a
   * service-role transport.
   */
  copy(input: { from: RecordRef; to: RecordRef }): AsyncResult<number>;
  /**
   * The record's conversation id, for Realtime (`conversationTopic`) and for
   * uploads to attach (`attachments` on subject `conversation`). `open` creates
   * it before the first comment; without it, `undefined` until then.
   */
  conversation(
    input: { subject: RecordRef } & { readonly open?: boolean },
  ): AsyncResult<string | undefined>;
  /**
   * Moves the caller's read marker on the record's comments forward; returns
   * where it is, or `undefined` before the first comment.
   */
  markRead(
    input: { subject: RecordRef } & { readonly readAt?: Temporal.Instant },
  ): AsyncResult<Temporal.Instant | undefined>;
  /** `create` with `parentId`. */
  reply(input: {
    subject: RecordRef;
    parentId: string;
    comment: Omit<NewComment<F>, "parentId">;
  }): AsyncResult<Comment<F>>;
  /** `resolve` with `resolved: false`. */
  reopen(id: string): AsyncResult<Comment<F>>;
}

/**
 * The user ids mentioned in a body written as `@[Ada](user:<user id>)` or
 * `@[Ada](<user id>)`, the markup mention inputs produce, in order and without
 * repeats.
 */
export function mentionsIn(body: string): readonly string[] {
  return parseMentions(body).users;
}

/** A row of `list_comments` or `create_comment`. */
export function commentOf(value: unknown): Comment {
  const row = recordOf(value, "comment");

  return {
    ...messageOf(row),
    subject: subjectRefOf(row["subject_type"], row["subject_id"]),
    taskId: optionalText(row["task_id"]),
  };
}

const notFound = (): ReturnType<typeof dbError> =>
  dbError("not_found", "No comment you can read has this id", {
    hint: "COMMENT_NOT_FOUND",
  });

/** Comments over the messaging core, as the caller. */
export function createComments<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: CommentsOptions<S>): Comments<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "comment fields");
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const mentionsOf = (body: string, rich: unknown): readonly string[] =>
    options.mentionsOf
      ? options.mentionsOf({ body, document: rich })
      : mentionsIn(body);

  const get = (id: string): AsyncResult<Comment<F>> =>
    call("get_comment", { message: id }, (value) =>
      value === null || value === undefined ? undefined : commentOf(value),
    ).andThen((comment) =>
      comment === undefined ? AsyncResult.err(notFound()) : fields.row(comment),
    );

  const conversation: Comments<F>["conversation"] = ({ subject, ...open }) =>
    tenant().andThen((organizationId) =>
      open.open === true
        ? call(
            "open_conversation",
            {
              tenant: organizationId,
              kind: "subject",
              attrs: { subjectType: subject.type, subjectId: subject.id },
              members: [],
            },
            (value) => optionalText(recordOf(value, "conversation")["id"]),
          )
        : call(
            "comment_conversation",
            {
              tenant: organizationId,
              subject_type: subject.type,
              subject_id: subject.id,
            },
            optionalText,
          ),
    );

  const client: Comments<F> = {
    create: ({ subject, comment }) =>
      tenant().andThen((organizationId) =>
        fields
          .args(comment.fields)
          .andThen((checked) =>
            call(
              "create_comment",
              {
                tenant: organizationId,
                subject_type: subject.type,
                subject_id: subject.id,
                body: comment.body,
                attrs: {
                  mentions: [
                    ...(comment.mentionIds ??
                      mentionsOf(comment.body, comment.document)),
                  ],
                  ...(comment.parentId === undefined
                    ? {}
                    : { parentId: comment.parentId }),
                  ...(comment.document === undefined
                    ? {}
                    : { document: comment.document }),
                  ...(comment.anchor === undefined
                    ? {}
                    : { anchor: comment.anchor }),
                  ...(checked === undefined ? {} : { fields: checked }),
                },
                attachments: [...(comment.attachmentIds ?? [])],
              },
              commentOf,
            ).andThen(fields.row),
          ),
      ),
    get,
    edit: ({ id, edit }) =>
      fields
        .args(edit.fields)
        .andThen((checked) =>
          call(
            "edit_message",
            {
              message: id,
              body: edit.body,
              attrs: {
                mentions: [
                  ...(edit.mentionIds ?? mentionsOf(edit.body, edit.document)),
                ],
                ...(edit.document === undefined
                  ? {}
                  : { document: edit.document }),
                ...(checked === undefined ? {} : { fields: checked }),
              },
            },
            () => undefined,
          ),
        )
        .andThen(() => get(id)),
    remove: (id) =>
      call("delete_message", { message: id }, (value) => value === true),
    resolve: ({ id, resolved = true }) =>
      call(
        "resolve_message",
        { message: id, resolved },
        () => undefined,
      ).andThen(() => get(id)),
    pin: ({ id, pinned = true }) =>
      call("pin_message", { message: id, pinned }, () => undefined).andThen(
        () => get(id),
      ),
    edits: (id) =>
      call("list_message_edits", { message: id }, (value) =>
        recordsOf(value, "list_message_edits").map(editOf),
      ),
    assign: ({ id, assignment = {} }) =>
      call(
        "assign_comment",
        {
          message: id,
          assignee: assignment.assigneeId ?? null,
          attrs: {
            ...assignment.attrs,
            ...(assignment.title === undefined
              ? {}
              : { title: assignment.title }),
            ...(assignment.body === undefined ? {} : { body: assignment.body }),
          },
        },
        (value) => {
          const task = optionalText(value);

          if (task === undefined) {
            throw new TypeError("assign_comment returned no work item id");
          }

          return task;
        },
      ),
    list: ({ subject, ...list }) =>
      tenant().andThen((organizationId) =>
        call(
          "list_comments",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            after: instantArg(pageOf(list).cursor),
            max_rows: list.limit,
            skip: list.offset,
            after_id: list.cursorId,
            ...(list.includeDeleted === undefined
              ? {}
              : { include_deleted: list.includeDeleted }),
          },
          (value) => recordsOf(value, "list_comments").map(commentOf),
        ).andThen(fields.rows),
      ),
    anchoredTo: ({ attachmentId, ...list }) =>
      call(
        "list_file_comments",
        { attachment: attachmentId, max_rows: list.limit },
        (value) => recordsOf(value, "list_file_comments").map(commentOf),
      ).andThen(fields.rows),
    counts: (subjects) =>
      tenant().andThen((organizationId) =>
        bySubjectType(subjects, (type, ids) =>
          call(
            "comment_counts",
            { tenant: organizationId, subject_type: type, subject_ids: ids },
            (value) => {
              const found = isRecord(value) ? value : {};

              return Object.fromEntries(
                ids.map((id) => [id, Number(found[id] ?? 0)]),
              );
            },
          ),
        ),
      ),
    copy: ({ from, to }) =>
      tenant().andThen((organizationId) =>
        call(
          "copy_comments",
          {
            tenant: organizationId,
            from_type: from.type,
            from_id: from.id,
            to_type: to.type,
            to_id: to.id,
          },
          (value) => Number(value ?? 0),
        ),
      ),
    conversation,
    markRead: ({ subject, ...read }) =>
      conversation({ subject }).andThen((id) =>
        id === undefined
          ? AsyncResult.ok(undefined)
          : call(
              "mark_read",
              {
                conversation: id,
                thread: null,
                read_at: instantArg(read.readAt) ?? null,
              },
              (value) => requiredInstant(value, "readAt"),
            ),
      ),
    reply: ({ subject, parentId, comment }) =>
      hooked.create({ subject, comment: { ...comment, parentId } }),
    reopen: (id) => hooked.resolve({ id, resolved: false }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Comments<F> = withBlockHooks(client, options.hooks, {
    block: "comments",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
