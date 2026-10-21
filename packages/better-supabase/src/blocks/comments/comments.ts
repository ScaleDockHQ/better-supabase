import type { Author } from "../../core/block-authors.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { BetterSupabase } from "../../core/define.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { CloudEvent, EventSink } from "../../events/index.ts";
import type { ListDefinition, ListQueryConfig } from "../../list/list-query.ts";
import type {
  AnyFunctions,
  AnyModels,
  SubjectRef,
  TableKey,
  TableMeta,
} from "../../schema/types.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";

import { authorOf } from "../../core/block-authors.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  bySubjectType,
  optionalSubjectRefOf,
  subjectRefOf,
} from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { stripTypePrefix } from "../../events/cloud-event.ts";
import { defineListQuery } from "../../list/list-query.ts";
import {
  blockCall,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  applyTemporal,
  pageOf,
} from "../shared.ts";

export interface CommentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockTemporalOptions, BlockTenantOptions {
  /**
   * A Standard Schema for the comment's extra columns
   * (`blocks.comments.options.extraColumns`), keyed by database name. It types
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
   * The user ids a comment mentions when the call passes no `mentions`, such as
   * the mention nodes of a rich-text `document`. Default `mentionsIn(body)`.
   */
  readonly mentionsOf?: (comment: {
    readonly body: string;
    readonly document: unknown;
  }) => readonly string[];
}

/** A comment. `F` types the extra columns the `fields` schema describes. */
export interface Comment<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: SubjectRef;
  /** `undefined` once the author's account is deleted. */
  readonly authorId: string | undefined;
  /**
   * The author's name and avatar from `profiles`; `undefined` without the
   * `profiles` module or once the account is deleted.
   */
  readonly author: Author | undefined;
  /** Empty for a deleted comment. */
  readonly body: string;
  /** The rich-text document an editor wrote, next to `body` as its plain text. */
  readonly document: unknown;
  readonly mentions: readonly string[];
  readonly parentId: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly editedAt: Temporal.Instant | undefined;
  readonly deletedAt: Temporal.Instant | undefined;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface NewComment<F extends object = Record<never, never>> {
  readonly body: string;
  /** A rich-text document (any JSON); keep `body` as its plain text. */
  readonly document?: unknown;
  /** User ids; default `mentionsOf`, or the ids `mentionsIn(body)` finds. */
  readonly mentions?: readonly string[];
  /** A reply: the parent must be on the same subject. */
  readonly parentId?: string;
  /** The extra columns to set, keyed by database name. */
  readonly fields?: Partial<F>;
}

export interface CommentEdit<F extends object = Record<never, never>> {
  readonly body: string;
  /**
   * A new document; `null` removes it, and leaving it out keeps the current
   * one.
   */
  readonly document?: unknown;
  /** Default `mentionsOf`, or the ids `mentionsIn(body)` finds. */
  readonly mentions?: readonly string[];
  /** The extra columns to set, keyed by database name; others keep their value. */
  readonly fields?: Partial<F>;
}

/**
 * Where a timeline entry comes from: `event` for an `activity_entries` row that
 * `activitySink()` wrote, `audit` for an audit log entry on the subject's row
 * (with the `audit` and `subjects` modules), `delivery` for a notification
 * delivery about the subject (with `notifications`) and `run` for a workflow
 * run on it (with `workflows`).
 */
export type ActivitySource = "event" | "audit" | "delivery" | "run";

const ACTIVITY_SOURCES: readonly ActivitySource[] = [
  "event",
  "audit",
  "delivery",
  "run",
];

function sourceOf(value: unknown): ActivitySource {
  return ACTIVITY_SOURCES.find((source) => source === value) ?? "event";
}

export interface ActivityEntry {
  /** An `activity_entries` id, or the audit entry's, delivery's or run's id. */
  readonly id: string;
  readonly source: ActivitySource;
  readonly organizationId: string;
  readonly type: string;
  readonly actorId: string | undefined;
  readonly subject: SubjectRef | undefined;
  readonly summary: string | undefined;
  readonly data: Readonly<Record<string, unknown>>;
  readonly occurredAt: Temporal.Instant;
}

export interface ActivityHistoryOptions extends CursorPageOptions<Temporal.Instant> {
  /** Entries before this instant, for paging back. */
  readonly cursor?: Temporal.Instant;
  /** Default 50, at most 500. */
  readonly limit?: number;
  /** The kinds of entry to return; all of them when left out. */
  readonly sources?: readonly ActivitySource[];
}

export interface ListCommentsOptions extends CursorPageOptions<Temporal.Instant> {
  /** Comments created after this instant, for polling a thread. */
  readonly cursor?: Temporal.Instant;
  /**
   * The id of the last comment you have, next to `cursor`, so comments created
   * in the same instant as it aren't skipped.
   */
  readonly cursorId?: string;
  /** Default 100, at most 500. */
  readonly limit?: number;
  /** Comments to skip, for page-number paging. */
  readonly offset?: number;
}

/**
 * `F` is the extra fields `options.fields` describes. Every method acts in the
 * block's `tenant`.
 */
export interface Comments<F extends object = Record<never, never>> {
  /** Posts a comment on `subject`. */
  create(subject: SubjectRef, comment: NewComment<F>): AsyncResult<Comment<F>>;
  /** Only the author edits; `not_found` when the caller can't see it. */
  edit(id: string, edit: CommentEdit<F>): AsyncResult<Comment<F>>;
  /** Soft-deletes (the author, or a member with `comments.moderate`). */
  remove(id: string): AsyncResult<boolean>;
  /** A subject's thread, oldest first, deleted comments as placeholders. */
  list(
    subject: SubjectRef,
    options?: ListCommentsOptions,
  ): AsyncResult<readonly Comment<F>[]>;
  /**
   * How many comments each subject has that the caller can read, deleted ones
   * left out, such as for a counter on each row of a list, keyed by
   * `subjectKey(subject)` (`type:id`). Subjects without comments are 0.
   */
  counts(
    subjects: readonly SubjectRef[],
  ): AsyncResult<Readonly<Record<string, number>>>;
  /**
   * Copies a subject's thread to another subject in the tenant, keeping
   * authors, times and replies; returns how many comments it copied. Needs a
   * service-role transport.
   */
  copy(from: SubjectRef, to: SubjectRef): AsyncResult<number>;
  /**
   * The activity feed of a tenant, newest first, or one subject's timeline with
   * `subject`. Members with `activity.read` see it. With the `subjects` module,
   * an entry on a registered subject type needs `can_subject` read, and a
   * subject's timeline also lists its audit log entries (`source: "audit"`)
   * when `audit` is installed with its read policy, the deliveries of
   * notifications about it (`source: "delivery"`, for members who also hold
   * `notifications.send`) and its workflow runs (`source: "run"`, as the runs'
   * read policy allows).
   */
  history(
    subject?: SubjectRef | null,
    options?: ActivityHistoryOptions,
  ): AsyncResult<readonly ActivityEntry[]>;
}

const MENTION =
  /@\[[^\]\n]{1,100}\]\(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)/gi;

/**
 * The user ids mentioned in a body written as `@[Ada](<user id>)`, the markup
 * mention inputs produce, in order and without repeats.
 */
export function mentionsIn(body: string): readonly string[] {
  return [
    ...new Set(
      [...body.matchAll(MENTION)].flatMap((match) =>
        match[1] ? [match[1].toLowerCase()] : [],
      ),
    ),
  ];
}

function commentOf(value: unknown): Comment {
  const row = recordOf(value, "comments");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    subject: subjectRefOf(row["subject_type"], row["subject_id"]),
    authorId: optionalText(row["author_id"]),
    author: authorOf(row["author"]),
    body: textOf(row["body"] ?? ""),
    document: row["document"] ?? null,
    mentions: stringsOf(row["mentions"]),
    parentId: optionalText(row["parent_id"]),
    createdAt: toInstant(textOf(row["created_at"])),
    editedAt: optionalInstant(row["edited_at"]),
    deletedAt: optionalInstant(row["deleted_at"]),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function activityOf(value: unknown): ActivityEntry {
  const row = recordOf(value, "activity_entries");

  return {
    id: textOf(row["id"]),
    source: sourceOf(row["source"]),
    organizationId: textOf(row["organization_id"]),
    type: textOf(row["type"]),
    actorId: optionalText(row["actor_id"]),
    subject: optionalSubjectRefOf(row["subject_type"], row["subject_id"]),
    summary: optionalText(row["summary"]),
    data: isRecord(row["data"]) ? row["data"] : {},
    occurredAt: toInstant(textOf(row["occurred_at"])),
  };
}

/** Comments over the `comments` module's functions, as the caller. */
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

  const client: Comments<F> = {
    create: (subject, comment) =>
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
                mentions:
                  comment.mentions ??
                  mentionsOf(comment.body, comment.document),
                parent: comment.parentId,
                document: comment.document,
                fields: checked,
              },
              commentOf,
            ).andThen(fields.row),
          ),
      ),
    edit: (id, edit) =>
      fields
        .args(edit.fields)
        .andThen((checked) =>
          call(
            "edit_comment",
            {
              id,
              body: edit.body,
              mentions: edit.mentions ?? mentionsOf(edit.body, edit.document),
              document: edit.document ?? undefined,
              ...(edit.document === null ? { clear_document: true } : {}),
              fields: checked,
            },
            (value) => value,
          ).andThen((value) =>
            value === null || value === undefined
              ? AsyncResult.err(
                  dbError("not_found", "No comment you can edit has this id", {
                    hint: "COMMENT_NOT_FOUND",
                  }),
                )
              : fields.row(commentOf(value)),
          ),
        ),
    remove: (id) => call("delete_comment", { id }, (value) => value === true),
    list: (subject, list = {}) =>
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
          },
          (value) => recordsOf(value, "list_comments").map(commentOf),
        ).andThen(fields.rows),
      ),
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
    copy: (from, to) =>
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
    history: (subject, history = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_activity",
          {
            tenant: organizationId,
            subject_type: subject?.type,
            subject_id: subject?.id,
            before: instantArg(pageOf(history).cursor),
            max_rows: history.limit,
            sources: history.sources ? [...history.sources] : undefined,
          },
          (value) => recordsOf(value, "list_activity").map(activityOf),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "comments",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/** What an activity entry says about an event; `null` skips the event. */
export interface ActivityDescription {
  readonly summary?: string;
  readonly actorId?: string;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly data?: Readonly<Record<string, unknown>>;
}

export interface ActivitySinkOptions {
  /**
   * A service-role transport: `record_activity()` is granted to `service_role`
   * only.
   */
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * The outbox `typePrefix`, stripped from the stored type. Default
   * `dev.better-supabase`.
   */
  readonly typePrefix?: string;
  /** Types to keep, exact or ending in `.*`. Default every event with a tenant. */
  readonly types?: readonly string[];
  /** Summarizes an event, or returns `null` to skip it. */
  readonly describe?: (
    event: CloudEvent,
    type: string,
  ) => ActivityDescription | null | undefined;
}

const matches = (patterns: readonly string[], type: string): boolean =>
  patterns.some((pattern) =>
    pattern.endsWith(".*")
      ? type.startsWith(pattern.slice(0, -1))
      : pattern === type,
  );

const firstText = (
  data: Readonly<Record<string, unknown>>,
  keys: readonly string[],
): string | undefined => {
  for (const key of keys) {
    const value = optionalText(data[key]);

    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
};

/** `comments/<id>` as `{ type: "comment", id }`, the shape block subjects use. */
function subjectOf(
  subject: string | undefined,
): { type: string; id: string } | undefined {
  const slash = subject?.indexOf("/") ?? -1;

  if (subject === undefined || slash < 1) {
    return undefined;
  }

  const plural = subject.slice(0, slash);

  return {
    type: plural.endsWith("s") ? plural.slice(0, -1) : plural,
    id: subject.slice(slash + 1),
  };
}

/**
 * An outbox sink that writes events into the activity feed:
 * `outbox.relay('activity', activitySink({ transport }))`. Events without a
 * tenant (`partitionkey`) are skipped, and a replayed event writes nothing.
 */
export function activitySink(options: ActivitySinkOptions): EventSink {
  const call = blockCall(options.transport, options.schema);

  return {
    async send(events) {
      const entries: Record<string, unknown>[] = [];

      for (const event of events) {
        const tenant = optionalText(event["partitionkey"]);

        if (tenant === undefined) {
          continue;
        }

        const type = stripTypePrefix(event.type, options.typePrefix);

        if (options.types && !matches(options.types, type)) {
          continue;
        }

        const described = options.describe ? options.describe(event, type) : {};

        if (described === null) {
          continue;
        }

        const data = isRecord(event.data) ? event.data : {};
        const subject = subjectOf(event.subject);
        entries.push({
          event_id: event.id,
          organization_id: tenant,
          type,
          actor_id:
            described?.actorId ??
            firstText(data, ["actorId", "authorId", "userId"]),
          subject_type:
            described?.subjectType ??
            optionalText(data["subjectType"]) ??
            subject?.type,
          subject_id:
            described?.subjectId ??
            optionalText(data["subjectId"]) ??
            subject?.id,
          summary: described?.summary,
          data: described?.data ?? data,
          occurred_at: event.time,
        });
      }

      if (entries.length > 0) {
        // A sink rejects on failure, so the relay retries the batch.
        await call(
          "record_activity",
          { batch: { entries } },
          () => undefined,
        ).orThrow();
      }
    },
  };
}

export type ActivitySort = "newest" | "oldest";

export type ActivityFacet = "type" | "actor" | "subjectType" | "subjectId";

const FACETS: readonly [ActivityFacet, string, string][] = [
  ["type", "type", "type"],
  ["actor", "actor_id", "actorId"],
  ["subjectType", "subject_type", "subjectType"],
  ["subjectId", "subject_id", "subjectId"],
];

/**
 * A cursor-paged list over `activity_entries` (generate types for the
 * `better_supabase` schema to get it in your models), newest first, filtered by
 * type, actor and subject. Members with `activity.read` see their tenants'
 * entries, less those on a registered subject that `can_subject` doesn't let
 * them read (with the `subjects` module). It reads the table, so it lists no
 * audit entries; `history()` does.
 */
export function activityListQuery<
  M extends AnyModels,
  D,
  Fn extends AnyFunctions,
  E,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, Fn, E>,
  table: T,
  options: { readonly pageSize?: number; readonly maxPageSize?: number } = {},
): ListDefinition<M, T, E, ActivitySort, ActivityFacet> {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];

  if (!meta) {
    throw new TypeError(`activityListQuery: unknown table "${table}"`);
  }

  const camel = meta.columns["occurredAt"] !== undefined;

  const facets: Record<string, string> = Object.fromEntries(
    FACETS.map(([key, snake, camelName]): [ActivityFacet, string] => [
      key,
      camel ? camelName : snake,
    ]).filter(([, column]) => meta.columns[column] !== undefined),
  );

  const occurredAt = camel ? "occurredAt" : "occurred_at";

  // SAFETY: defineListQuery checks every column against the table's meta
  // and throws for one the table lacks; facets keeps only columns it has.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the column names are known only at runtime (camel or snake casing), so the config can't be typed against M.
  const config = {
    facets,
    sorts: {
      newest: [{ [occurredAt]: "desc" }, { id: "desc" }],
      oldest: [{ [occurredAt]: "asc" }, { id: "asc" }],
    },
    defaultSort: "newest",
    pagination: "cursor",
    ...(options.pageSize === undefined ? {} : { pageSize: options.pageSize }),
    ...(options.maxPageSize === undefined
      ? {}
      : { maxPageSize: options.maxPageSize }),
  } as unknown as ListQueryConfig<
    M,
    T,
    ActivitySort,
    ActivityFacet,
    false,
    "cursor"
  >;

  return defineListQuery(betterSupabase, table, config);
}
