import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireOrganization } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

const STATUSES = ["draft", "scheduled", "published", "archived"] as const;

const APPROVAL_STATUSES = [
  "pending",
  "approved",
  "rejected",
  "cancelled",
  "expired",
] as const;

/** Where an entry stands. Only published entries reach the public reads. */
export type ContentStatus = (typeof STATUSES)[number];

/** The state of an entry's latest publish request. */
export type ContentApprovalStatus = (typeof APPROVAL_STATUSES)[number];

/** An entry's body: the JSON document an editor writes, an object or a list. */
export type ContentBody =
  | Readonly<Record<string, unknown>>
  | readonly unknown[];

/** Another locale of the same entry. */
export interface ContentTranslation {
  readonly id?: string;
  readonly locale: string;
  readonly slug: string;
  /** Left out by the public reads, which list published translations only. */
  readonly status?: ContentStatus;
}

export interface ContentEntry {
  readonly id: string;
  readonly organizationId: string;
  readonly type: string;
  readonly locale: string;
  readonly slug: string;
  readonly title: string;
  readonly summary?: string;
  readonly body: ContentBody;
  readonly status: ContentStatus;
  /** When a scheduled entry goes live, or the time a publish request asks for. */
  readonly publishAt?: Temporal.Instant;
  readonly publishedAt?: Temporal.Instant;
  readonly authorId?: string;
  /** Shared by the entry's translations. */
  readonly translationGroupId: string;
  /** An attachment of the organization, when the attachments block is installed. */
  readonly coverAttachmentId?: string;
  /** The latest publish request under `options.requireApproval`. */
  readonly approvalId?: string;
  readonly approvalStatus?: ContentApprovalStatus;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The other locales; `get` fills it in. */
  readonly translations?: readonly ContentTranslation[];
}

export interface ContentEntryInput {
  /** One of `options.types`. */
  readonly type: string;
  /** One of `options.locales`; default the first. */
  readonly locale?: string;
  /** Lowercase letters and digits joined by dashes, with `/` between segments. */
  readonly slug: string;
  readonly title: string;
  readonly summary?: string | null;
  readonly body?: ContentBody;
  readonly coverAttachmentId?: string | null;
  /** An entry of the same type this one translates. */
  readonly translationOf?: string;
}

/** What `update` changes; keys left out keep their value. */
export type ContentEntryUpdate = Partial<
  Pick<
    ContentEntryInput,
    "slug" | "title" | "summary" | "body" | "coverAttachmentId"
  >
>;

export interface ContentFilter {
  readonly type?: string;
  readonly locale?: string;
  readonly status?: ContentStatus;
  readonly translationGroupId?: string;
  /** Matches the title or slug. */
  readonly query?: string;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** A published entry, as anyone reads it. */
export interface PublishedContentEntry {
  readonly id: string;
  readonly type: string;
  readonly locale: string;
  readonly slug: string;
  readonly title: string;
  readonly summary?: string;
  /** Only `published` returns the body; lists leave it out. */
  readonly body?: ContentBody;
  readonly coverAttachmentId?: string;
  readonly translationGroupId: string;
  readonly publishedAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The published translations; `published` fills it in. */
  readonly translations?: readonly ContentTranslation[];
}

export interface PublishedContentFilter {
  /** Every type when left out. */
  readonly type?: string;
  /** Default the first of `options.locales`. */
  readonly locale?: string;
  /** 1 to 100. Default 20. */
  readonly limit?: number;
  /** Entries published before this time, to page back. */
  readonly before?: Temporal.Instant;
}

export interface Content {
  /** Writes a draft; needs `content.write`. */
  create(input: ContentEntryInput): AsyncResult<ContentEntry>;
  /**
   * Changes an entry. A change to a draft withdraws its pending publish
   * request. Under `requireApproval`, a scheduled or published entry needs
   * `content.publish`.
   */
  update(entryId: string, input: ContentEntryUpdate): AsyncResult<ContentEntry>;
  /** Takes an entry down; a live or scheduled one needs `content.publish`. */
  archive(entryId: string): AsyncResult<ContentEntry>;
  /** The entry with its translations, or null when the caller can't read it. */
  get(entryId: string): AsyncResult<ContentEntry | null>;
  list(filter?: ContentFilter): AsyncResult<readonly ContentEntry[]>;
  /**
   * Publishes an entry now; needs `content.publish`. Under `requireApproval` a
   * member's call opens a publish request and returns the waiting draft.
   */
  publish(entryId: string): AsyncResult<ContentEntry>;
  /**
   * Schedules an entry to go live at `at`, or unschedules it with null. Under
   * `requireApproval` a member's call opens a publish request.
   */
  schedule(
    entryId: string,
    at: Temporal.Instant | null,
  ): AsyncResult<ContentEntry>;
  /** Publishes the scheduled entries that are due; service role only. */
  publishDue(): AsyncResult<number>;
  /** A published entry, falling back to the default locale; anyone may call it. */
  published(input: {
    readonly type: string;
    readonly slug: string;
    readonly locale?: string;
  }): AsyncResult<PublishedContentEntry | null>;
  /** Published entries, newest first; anyone may call it. */
  listPublished(
    filter?: PublishedContentFilter,
  ): AsyncResult<readonly PublishedContentEntry[]>;
}

export interface ContentOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<Content>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const bodyOf = (value: unknown): ContentBody =>
  Array.isArray(value) ? value : isRecord(value) ? value : {};

function translationsOf(value: unknown): readonly ContentTranslation[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(isRecord).map((row) => {
    const id = optionalText(row["id"]);

    return {
      locale: textOf(row["locale"]),
      slug: textOf(row["slug"]),
      ...(id === undefined ? {} : { id }),
      ...(row["status"] === undefined
        ? {}
        : { status: enumOrThrow(row["status"], STATUSES, "content status") }),
    };
  });
}

function entryOf(value: unknown, fn: string): ContentEntry {
  const row = recordOf(value, fn);

  const text = (key: string): Record<string, string> => {
    const item = optionalText(row[key]);

    return item === undefined ? {} : { [key]: item };
  };

  const instant = (key: string): Record<string, Temporal.Instant> => {
    const item = optionalInstant(row[key]);

    return item === undefined ? {} : { [key]: item };
  };

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    type: textOf(row["type"]),
    locale: textOf(row["locale"]),
    slug: textOf(row["slug"]),
    title: textOf(row["title"]),
    body: bodyOf(row["body"]),
    status: enumOrThrow(row["status"], STATUSES, "content status"),
    translationGroupId: textOf(row["translationGroupId"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...text("summary"),
    ...text("authorId"),
    ...text("coverAttachmentId"),
    ...text("approvalId"),
    ...text("createdBy"),
    ...instant("publishAt"),
    ...instant("publishedAt"),
    ...(row["approvalStatus"] === null || row["approvalStatus"] === undefined
      ? {}
      : {
          approvalStatus: enumOrThrow(
            row["approvalStatus"],
            APPROVAL_STATUSES,
            "approval status",
          ),
        }),
    ...(Array.isArray(row["translations"])
      ? { translations: translationsOf(row["translations"]) }
      : {}),
  };
}

function publishedOf(value: unknown, fn: string): PublishedContentEntry {
  const row = recordOf(value, fn);
  const summary = optionalText(row["summary"]);
  const cover = optionalText(row["coverAttachmentId"]);

  return {
    id: textOf(row["id"]),
    type: textOf(row["type"]),
    locale: textOf(row["locale"]),
    slug: textOf(row["slug"]),
    title: textOf(row["title"]),
    translationGroupId: textOf(row["translationGroupId"]),
    publishedAt: requiredInstant(row["publishedAt"], "publishedAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...(summary === undefined ? {} : { summary }),
    ...(cover === undefined ? {} : { coverAttachmentId: cover }),
    ...(row["body"] === undefined ? {} : { body: bodyOf(row["body"]) }),
    ...(Array.isArray(row["translations"])
      ? { translations: translationsOf(row["translations"]) }
      : {}),
  };
}

/**
 * Typed, localized content entries: drafts that are scheduled and published,
 * optionally through approvals, and public reads of what is published.
 */
export function createContent(options: ContentOptions): Content {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireOrganization(options.tenant);
  const entry = (fn: string) => (value: unknown) => entryOf(value, fn);

  const client: Content = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_content_entry",
          { tenant: organizationId, attrs: definedOf(input) },
          entry("create_content_entry"),
        ),
      ),
    update: (entryId, input) =>
      call(
        "update_content_entry",
        { entry_id: entryId, attrs: definedOf(input) },
        entry("update_content_entry"),
      ),
    archive: (entryId) =>
      call(
        "archive_content_entry",
        { entry_id: entryId },
        entry("archive_content_entry"),
      ),
    get: (entryId) =>
      call("get_content_entry", { entry_id: entryId }, (value) =>
        value === null || value === undefined
          ? null
          : entryOf(value, "get_content_entry"),
      ),
    list: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_content_entries",
          { tenant: organizationId, filter: definedOf(filter) },
          (value) =>
            recordsOf(value, "list_content_entries").map(
              entry("list_content_entries"),
            ),
        ),
      ),
    publish: (entryId) =>
      call(
        "publish_content_entry",
        { entry_id: entryId },
        entry("publish_content_entry"),
      ),
    schedule: (entryId, at) =>
      call(
        "schedule_content_entry",
        { entry_id: entryId, at: instantArg(at) },
        entry("schedule_content_entry"),
      ),
    publishDue: () =>
      call("publish_due_content_entries", {}, (value) => Number(value ?? 0)),
    published: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "public_content_entry",
          {
            tenant: organizationId,
            type: input.type,
            slug: input.slug,
            locale: input.locale ?? null,
          },
          (value) =>
            value === null || value === undefined
              ? null
              : publishedOf(value, "public_content_entry"),
        ),
      ),
    listPublished: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "public_content_entries",
          {
            tenant: organizationId,
            type: filter.type ?? null,
            locale: filter.locale ?? null,
            page_size: filter.limit ?? null,
            before:
              filter.before === undefined ? null : instantArg(filter.before),
          },
          (value) =>
            recordsOf(value, "public_content_entries").map((row) =>
              publishedOf(row, "public_content_entries"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "content",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
