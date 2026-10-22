import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
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

export interface ModerationOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Moderation>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const STATUSES = ["pending", "visible", "hidden", "removed"] as const;

/** Where moderated content stands. `pending` waits for a first decision. */
export type ModerationStatus = (typeof STATUSES)[number];

const DECISIONS = ["approve", "hide", "remove", "restore", "ban"] as const;

/**
 * A moderator's decision: `approve` and `restore` show the content, `hide`
 * hides it, `remove` removes it, and `ban` removes it and bans its author.
 */
export type ModerationDecision = (typeof DECISIONS)[number];

const ACTIONS = [
  "submit",
  "approve",
  "hide",
  "remove",
  "restore",
  "ban",
  "auto_hide",
] as const;

/** An entry of an item's log: a decision, a resubmission or an automatic hide. */
export type ModerationActionKind = (typeof ACTIONS)[number];

const REPORT_STATUSES = ["open", "resolved", "dismissed"] as const;

/** A subject under moderation. */
export interface ModerationItem {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: SubjectRef;
  readonly authorId?: string;
  readonly status: ModerationStatus;
  readonly openReports: number;
  /** Why it is hidden or removed. */
  readonly reason?: string;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ModerationReport {
  readonly id: string;
  readonly organizationId: string;
  readonly itemId: string;
  readonly reporterId?: string;
  readonly reason: string;
  readonly note?: string;
  /**
   * `resolved` when the content was hidden or removed, `dismissed` when it
   * stayed.
   */
  readonly status: (typeof REPORT_STATUSES)[number];
  readonly resolvedBy?: string;
  readonly resolvedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface ModerationAction {
  readonly id: string;
  readonly action: ModerationActionKind;
  readonly fromStatus?: ModerationStatus;
  readonly toStatus: ModerationStatus;
  readonly reason?: string;
  /** Unset for the automatic hide. */
  readonly actorId?: string;
  readonly createdAt: Temporal.Instant;
}

/** An item with its latest 100 reports and log entries, newest first. */
export interface ModerationItemDetail extends ModerationItem {
  readonly reports: readonly ModerationReport[];
  readonly actions: readonly ModerationAction[];
}

export interface ModerationBan {
  readonly id: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly reason?: string;
  readonly bannedBy?: string;
  /** Unset for a ban without an end. */
  readonly expiresAt?: Temporal.Instant;
  readonly liftedBy?: string;
  readonly liftedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface ModerationQueueFilter {
  /**
   * Default: what needs a moderator, pending content and content with open
   * reports.
   */
  readonly status?: ModerationStatus;
  readonly subjectType?: string;
  /** Default 50, at most 200. */
  readonly pageSize?: number;
  /** Items changed before this instant, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface Moderation {
  /**
   * Reports a subject. Reporting it again while the first report is open
   * returns that report. `autoHidden` is true when this report reached the
   * auto-hide threshold.
   */
  report(
    subject: SubjectRef,
    report: { readonly reason: string; readonly note?: string },
  ): AsyncResult<ModerationReport & { readonly autoHidden: boolean }>;
  /** The review queue, most recently changed first. */
  queue(filter?: ModerationQueueFilter): AsyncResult<readonly ModerationItem[]>;
  /**
   * A subject's item with its reports and log, or `null` when nothing moderated
   * it.
   */
  item(subject: SubjectRef): AsyncResult<ModerationItemDetail | null>;
  /** Decides on an item. `ban` needs the ban permission as well. */
  decide(
    itemId: string,
    decision: ModerationDecision,
    options?: { readonly reason?: string },
  ): AsyncResult<ModerationItem>;
  /**
   * The statuses of the subjects that are not visible, by id, for filtering a
   * list. Visible and unmoderated subjects are left out. At most 500 ids.
   */
  statuses(
    subjectType: string,
    ids: readonly string[],
  ): AsyncResult<Readonly<Record<string, ModerationStatus>>>;
  /** Bans a user in the organization, until `expiresAt` or for good. */
  ban(
    userId: string,
    options?: {
      readonly reason?: string;
      readonly expiresAt?: Temporal.Instant;
    },
  ): AsyncResult<ModerationBan>;
  /** Lifts a ban; `false` when it was already lifted. */
  unban(banId: string): AsyncResult<boolean>;
  /** The organization's bans, newest first: active ones unless `active: false`. */
  bans(filter?: {
    readonly active?: boolean;
    readonly pageSize?: number;
  }): AsyncResult<readonly ModerationBan[]>;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): Partial<Record<K, V>> {
  if (value === undefined) {
    return {};
  }

  const out: Partial<Record<K, V>> = {};
  out[key] = value;

  return out;
}

function itemOf(value: unknown, fn: string): ModerationItem {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    status: enumOrThrow(row["status"], STATUSES, "moderation status"),
    openReports: Number(row["openReports"] ?? 0),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("authorId", optionalText(row["authorId"])),
    ...optional("reason", optionalText(row["reason"])),
    ...optional("decidedBy", optionalText(row["decidedBy"])),
    ...optional("decidedAt", optionalInstant(row["decidedAt"])),
  };
}

function reportOf(value: unknown, fn: string): ModerationReport {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    itemId: textOf(row["itemId"]),
    reason: textOf(row["reason"]),
    status: enumOrThrow(row["status"], REPORT_STATUSES, "report status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("reporterId", optionalText(row["reporterId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("resolvedBy", optionalText(row["resolvedBy"])),
    ...optional("resolvedAt", optionalInstant(row["resolvedAt"])),
  };
}

function actionOf(value: unknown, fn: string): ModerationAction {
  const row = recordOf(value, fn);
  const from = optionalText(row["fromStatus"]);

  return {
    id: textOf(row["id"]),
    action: enumOrThrow(row["action"], ACTIONS, "moderation action"),
    toStatus: enumOrThrow(row["toStatus"], STATUSES, "moderation status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional(
      "fromStatus",
      from === undefined
        ? undefined
        : enumOrThrow(from, STATUSES, "moderation status"),
    ),
    ...optional("reason", optionalText(row["reason"])),
    ...optional("actorId", optionalText(row["actorId"])),
  };
}

function banOf(value: unknown, fn: string): ModerationBan {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("reason", optionalText(row["reason"])),
    ...optional("bannedBy", optionalText(row["bannedBy"])),
    ...optional("expiresAt", optionalInstant(row["expiresAt"])),
    ...optional("liftedBy", optionalText(row["liftedBy"])),
    ...optional("liftedAt", optionalInstant(row["liftedAt"])),
  };
}

function statusesOf(
  value: unknown,
): Readonly<Record<string, ModerationStatus>> {
  const out: Record<string, ModerationStatus> = {};

  if (isRecord(value)) {
    for (const [id, status] of Object.entries(value)) {
      out[id] = enumOrThrow(status, STATUSES, "moderation status");
    }
  }

  return out;
}

/** The `moderation` SQL module as typed calls. */
export function createModeration(options: ModerationOptions): Moderation {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Moderation = {
    report: (subject, report) =>
      tenant().andThen((organizationId) =>
        call(
          "report_content",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            reason: report.reason,
            note: report.note ?? null,
          },
          (value) => ({
            ...reportOf(value, "report_content"),
            autoHidden:
              recordOf(value, "report_content")["autoHidden"] === true,
          }),
        ),
      ),
    queue: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "moderation_queue",
          {
            tenant: organizationId,
            status: filter.status ?? null,
            subject_type: filter.subjectType ?? null,
            page_size: filter.pageSize ?? null,
            before: instantArg(filter.before) ?? null,
          },
          (value) =>
            recordsOf(value, "moderation_queue").map((row) =>
              itemOf(row, "moderation_queue"),
            ),
        ),
      ),
    item: (subject) =>
      tenant().andThen((organizationId) =>
        call(
          "moderation_item",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) => {
            if (!isRecord(value)) {
              return null;
            }

            const fn = "moderation_item";

            return {
              ...itemOf(value, fn),
              reports: recordsOf(value["reports"] ?? [], fn).map((row) =>
                reportOf(row, fn),
              ),
              actions: recordsOf(value["actions"] ?? [], fn).map((row) =>
                actionOf(row, fn),
              ),
            };
          },
        ),
      ),
    decide: (itemId, decision, decide = {}) =>
      call(
        "moderate",
        { item_id: itemId, action: decision, reason: decide.reason ?? null },
        (value) => itemOf(value, "moderate"),
      ),
    statuses: (subjectType, ids) =>
      tenant().andThen((organizationId) =>
        call(
          "moderation_statuses",
          {
            tenant: organizationId,
            subject_type: subjectType,
            subject_ids: [...ids],
          },
          statusesOf,
        ),
      ),
    ban: (userId, ban = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "ban_user",
          {
            tenant: organizationId,
            user_id: userId,
            reason: ban.reason ?? null,
            expires_at: instantArg(ban.expiresAt) ?? null,
          },
          (value) => banOf(value, "ban_user"),
        ),
      ),
    unban: (banId) =>
      call("unban_user", { ban_id: banId }, (value) => value === true),
    bans: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_bans",
          {
            tenant: organizationId,
            active: filter.active ?? true,
            page_size: filter.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_bans").map((row) => banOf(row, "list_bans")),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "moderation",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
