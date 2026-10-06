import type { BlockTransport } from "../../core/block-transport.ts";
import type { BetterSupabase } from "../../core/define.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { CloudEvent, EventSink } from "../../events/index.ts";
import type { ListDefinition, ListQueryConfig } from "../../list/list-query.ts";
import type {
  AnyFunctions,
  AnyModels,
  TableKey,
  TableMeta,
} from "../../schema/types.ts";

import { dbError } from "../../core/errors.ts";
import { type AsyncResult, err, ok } from "../../core/result.ts";
import { defineListQuery } from "../../list/list-query.ts";
import {
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

export interface CommentsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.comments.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * The user ids a comment mentions when the call passes no `mentions`,
   * such as the mention nodes of a rich-text `document`. Default
   * `mentionsIn(body)`.
   */
  readonly mentionsOf?: (comment: {
    readonly body: string;
    readonly document: unknown;
  }) => readonly string[];
}

export interface Comment {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `undefined` once the author's account is deleted. */
  readonly authorId: string | undefined;
  /** Empty for a deleted comment. */
  readonly body: string;
  /** The rich-text document an editor wrote, next to `body` as its plain text. */
  readonly document: unknown;
  readonly mentions: readonly string[];
  readonly parentId: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly editedAt: Temporal.Instant | undefined;
  readonly deletedAt: Temporal.Instant | undefined;
}

export interface NewComment {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly body: string;
  /** A rich-text document (any JSON); keep `body` as its plain text. */
  readonly document?: unknown;
  /** User ids; default `mentionsOf`, or the ids `mentionsIn(body)` finds. */
  readonly mentions?: readonly string[];
  /** A reply: the parent must be on the same subject. */
  readonly parentId?: string;
}

export interface CommentEdit {
  readonly body: string;
  /** A new document; `null` removes it, and leaving it out keeps the current one. */
  readonly document?: unknown;
  /** Default `mentionsOf`, or the ids `mentionsIn(body)` finds. */
  readonly mentions?: readonly string[];
}

export interface ActivityEntry {
  readonly id: string;
  readonly organizationId: string;
  readonly type: string;
  readonly actorId: string | undefined;
  readonly subjectType: string | undefined;
  readonly subjectId: string | undefined;
  readonly summary: string | undefined;
  readonly data: Readonly<Record<string, unknown>>;
  readonly occurredAt: Temporal.Instant;
}

export interface ActivityHistoryOptions {
  /** Entries before this instant, for paging back. */
  readonly before?: Temporal.Instant;
  /** Default 50, at most 500. */
  readonly limit?: number;
}

export interface ListCommentsOptions {
  /** Comments created after this instant, for polling a thread. */
  readonly after?: Temporal.Instant;
  /** Default 100, at most 500. */
  readonly limit?: number;
}

export interface Comments {
  create(comment: NewComment): AsyncResult<Comment>;
  /** Only the author edits; `not_found` when the caller can't see it. */
  edit(id: string, edit: CommentEdit): AsyncResult<Comment>;
  /** Soft-deletes (the author, or a member with `comments.moderate`). */
  remove(id: string): AsyncResult<boolean>;
  /** A subject's thread, oldest first, deleted comments as placeholders. */
  list(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    options?: ListCommentsOptions,
  ): AsyncResult<readonly Comment[]>;
  /**
   * Copies a subject's thread to another subject in the tenant, keeping
   * authors, times and replies; returns how many comments it copied. Needs a
   * service-role transport.
   */
  copy(
    organizationId: string,
    from: { readonly type: string; readonly id: string },
    to: { readonly type: string; readonly id: string },
  ): AsyncResult<number>;
  /**
   * The activity feed of a tenant, newest first, or one subject's timeline
   * with `subject`. Members with `activity.read` see it.
   */
  history(
    organizationId: string,
    subject?: { readonly type: string; readonly id: string },
    options?: ActivityHistoryOptions,
  ): AsyncResult<readonly ActivityEntry[]>;
}

const MENTION =
  /@\[[^\]\n]{1,100}\]\(([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)/gi;

/**
 * The user ids mentioned in a body written as `@[Ada](<user id>)`, the
 * markup mention inputs produce, in order and without repeats.
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
    subjectType: textOf(row["subject_type"]),
    subjectId: textOf(row["subject_id"]),
    authorId: optionalText(row["author_id"]),
    body: textOf(row["body"] ?? ""),
    document: row["document"] ?? null,
    mentions: stringsOf(row["mentions"]),
    parentId: optionalText(row["parent_id"]),
    createdAt: toInstant(textOf(row["created_at"])),
    editedAt: optionalInstant(row["edited_at"]),
    deletedAt: optionalInstant(row["deleted_at"]),
  };
}

function activityOf(value: unknown): ActivityEntry {
  const row = recordOf(value, "activity_entries");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    type: textOf(row["type"]),
    actorId: optionalText(row["actor_id"]),
    subjectType: optionalText(row["subject_type"]),
    subjectId: optionalText(row["subject_id"]),
    summary: optionalText(row["summary"]),
    data: isRecord(row["data"]) ? row["data"] : {},
    occurredAt: toInstant(textOf(row["occurred_at"])),
  };
}

/** Comments over the `comments` module's functions, as the caller. */
export function createComments(options: CommentsOptions): Comments {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const mentionsOf = (body: string, document: unknown): readonly string[] =>
    options.mentionsOf
      ? options.mentionsOf({ body, document })
      : mentionsIn(body);
  return {
    create: (comment) =>
      call(
        "create_comment",
        {
          tenant: comment.organizationId,
          subject_type: comment.subjectType,
          subject_id: comment.subjectId,
          body: comment.body,
          mentions:
            comment.mentions ?? mentionsOf(comment.body, comment.document),
          parent: comment.parentId,
          document: comment.document,
        },
        commentOf,
      ),
    edit: (id, edit) =>
      call(
        "edit_comment",
        {
          id,
          body: edit.body,
          mentions: edit.mentions ?? mentionsOf(edit.body, edit.document),
          document: edit.document ?? undefined,
          ...(edit.document === null ? { clear_document: true } : {}),
        },
        (value) => value,
      ).andThen((value) =>
        Promise.resolve(
          value === null || value === undefined
            ? err(
                dbError("not_found", "No comment you can edit has this id", {
                  hint: "COMMENT_NOT_FOUND",
                }),
              )
            : ok(commentOf(value)),
        ),
      ),
    remove: (id) => call("delete_comment", { id }, (value) => value === true),
    list: (organizationId, subjectType, subjectId, list = {}) =>
      call(
        "list_comments",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          after: instantArg(list.after),
          max_rows: list.limit,
        },
        (value) => recordsOf(value, "list_comments").map(commentOf),
      ),
    copy: (organizationId, from, to) =>
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
    history: (organizationId, subject, history = {}) =>
      call(
        "list_activity",
        {
          tenant: organizationId,
          subject_type: subject?.type,
          subject_id: subject?.id,
          before: instantArg(history.before),
          max_rows: history.limit,
        },
        (value) => recordsOf(value, "list_activity").map(activityOf),
      ),
  };
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
  /** A service-role transport: `record_activity()` is granted to `service_role` only. */
  readonly transport: BlockTransport;
  readonly schema?: string;
  /** The outbox `typePrefix`, stripped from the stored type. Default `dev.better-supabase`. */
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
    if (value !== undefined) return value;
  }
  return undefined;
};

/** `comments/<id>` as `{ type: "comment", id }`, the shape block subjects use. */
function subjectOf(
  subject: string | undefined,
): { type: string; id: string } | undefined {
  const slash = subject?.indexOf("/") ?? -1;
  if (subject === undefined || slash < 1) return undefined;
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
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;
  return {
    async send(events) {
      const entries: Record<string, unknown>[] = [];
      for (const event of events) {
        const tenant = optionalText(event["partitionkey"]);
        if (tenant === undefined) continue;
        const type = event.type.startsWith(prefix)
          ? event.type.slice(prefix.length)
          : event.type;
        if (options.types && !matches(options.types, type)) continue;
        const described = options.describe ? options.describe(event, type) : {};
        if (described === null) continue;
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
        await options.transport.call(schema, "record_activity", {
          batch: { entries },
        });
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
 * `better_supabase` schema to get it in your models), newest first,
 * filtered by type, actor and subject. Members with `activity.read` see
 * their tenants' entries.
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
): ListDefinition<M, T, E, ActivitySort, ActivityFacet, false, "cursor"> {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
  if (!meta) throw new TypeError(`activityListQuery: unknown table "${table}"`);
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
