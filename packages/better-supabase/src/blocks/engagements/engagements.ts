import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** A record an engagement is on. */
export interface EngagementSubject {
  readonly type: string;
  readonly id: string;
}

/** A call, email, meeting, note or task logged on one or more records. */
export interface Engagement {
  readonly id: string;
  readonly organizationId: string;
  /** `call`, `email`, `meeting`, `note`, `task` or a configured type. */
  readonly type: string;
  readonly title: string;
  readonly body?: string;
  /** How it went, such as `connected`, `no_answer` or `replied`. */
  readonly outcome?: string;
  readonly ownerId?: string;
  readonly dueAt?: Temporal.Instant;
  readonly doneAt?: Temporal.Instant;
  readonly durationSeconds?: number;
  /** The id in the system it came from, such as a mail or calendar provider. */
  readonly externalRef?: string;
  /** The records it is on; the first is its main record. */
  readonly subjects: readonly EngagementSubject[];
  /** Open and past its due time. */
  readonly overdue: boolean;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** The fields of a write. On update, left out keeps the value and `null` clears it. */
export interface EngagementInput {
  readonly type?: string;
  readonly title?: string;
  readonly body?: string | null;
  readonly outcome?: string | null;
  /** Defaults to the caller on `log`. */
  readonly ownerId?: string | null;
  readonly dueAt?: Temporal.Instant | null;
  readonly doneAt?: Temporal.Instant | null;
  readonly durationSeconds?: number | null;
  /** Logging the same `externalRef` again updates the engagement. */
  readonly externalRef?: string | null;
}

export interface Engagements {
  /** Logs an engagement on the records in `subjects`, the first being its main record. */
  log(
    organizationId: string,
    input: EngagementInput & { readonly type: string; readonly title: string },
    subjects: readonly EngagementSubject[],
  ): AsyncResult<Engagement>;
  /** Changes an engagement, and its records when `subjects` is given. */
  update(
    id: string,
    input: EngagementInput,
    subjects?: readonly EngagementSubject[],
  ): AsyncResult<Engagement>;
  /** Marks it done now, with an outcome, or open again with `done: false`. */
  complete(
    id: string,
    options?: { readonly done?: boolean; readonly outcome?: string },
  ): AsyncResult<Engagement>;
  remove(id: string): AsyncResult<boolean>;
  /** A record's engagements, newest first (50 by default, at most 200). */
  of(
    subject: EngagementSubject,
    options?: {
      readonly types?: readonly string[];
      readonly before?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<Engagement[]>;
  /** The next open engagement with a due time on a record, or `undefined`. */
  next(subject: EngagementSubject): AsyncResult<Engagement | undefined>;
  /** A member's open engagements, earliest due first. Default: the caller's. */
  open(
    organizationId: string,
    options?: {
      readonly ownerId?: string;
      readonly dueBefore?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<Engagement[]>;
}

export interface EngagementsOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `sql.modules.engagements.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Engagements>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function engagementOf(value: unknown): Engagement {
  const row = recordOf(value, "engagement");
  const optional = {
    body: optionalText(row["body"]),
    outcome: optionalText(row["outcome"]),
    ownerId: optionalText(row["owner_user_id"]),
    dueAt: optionalInstant(row["due_at"]),
    doneAt: optionalInstant(row["done_at"]),
    durationSeconds:
      typeof row["duration_seconds"] === "number"
        ? row["duration_seconds"]
        : undefined,
    externalRef: optionalText(row["external_ref"]),
    createdBy: optionalText(row["created_by"]),
  };
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    type: textOf(row["type"]),
    title: textOf(row["title"]),
    subjects: recordsOf(row["subjects"], "engagement subjects").map(
      (subject) => ({
        type: textOf(subject["type"]),
        id: textOf(subject["id"]),
      }),
    ),
    overdue: row["overdue"] === true,
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    ...Object.fromEntries(
      Object.entries(optional).filter(([, value]) => value !== undefined),
    ),
  };
}

/** The attrs of a write: the keys the input sets, instants as ISO text. */
function attrsOf(input: EngagementInput): Record<string, unknown> {
  const { dueAt, doneAt, ...rest } = input;
  return {
    ...rest,
    ...(dueAt === undefined ? {} : { dueAt: instantArg(dueAt) ?? null }),
    ...(doneAt === undefined ? {} : { doneAt: instantArg(doneAt) ?? null }),
  };
}

const subjectsArg = (
  subjects: readonly EngagementSubject[],
): { type: string; id: string }[] =>
  subjects.map((subject) => ({ type: subject.type, id: subject.id }));

/**
 * The engagements block: calls, emails, meetings, notes and tasks on any
 * record registered in `config.subjects`, for a record's activity panel, a
 * "next step" and a member's task list.
 */
export function createEngagements(options: EngagementsOptions): Engagements {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Engagements = {
    log: (organizationId, input, subjects) =>
      call(
        "log_engagement",
        {
          tenant: organizationId,
          attrs: attrsOf(input),
          subjects: subjectsArg(subjects),
        },
        engagementOf,
      ),
    update: (id, input, subjects) =>
      call(
        "update_engagement",
        {
          engagement: id,
          attrs: attrsOf(input),
          subjects: subjects === undefined ? null : subjectsArg(subjects),
        },
        engagementOf,
      ),
    complete: (id, complete = {}) =>
      call(
        "complete_engagement",
        {
          engagement: id,
          done: complete.done ?? true,
          outcome: complete.outcome ?? null,
        },
        engagementOf,
      ),
    remove: (id) =>
      call("delete_engagement", { engagement: id }, (value) => value === true),
    of: (subject, list = {}) =>
      call(
        "engagements_of",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          types: list.types === undefined ? null : [...list.types],
          before: instantArg(list.before) ?? null,
          page_size: list.limit ?? null,
        },
        (value) => recordsOf(value, "engagements_of").map(engagementOf),
      ),
    next: (subject) =>
      call(
        "next_engagement",
        { subject_type: subject.type, subject_id: subject.id },
        (value) => (value === null ? undefined : engagementOf(value)),
      ),
    open: (organizationId, list = {}) =>
      call(
        "open_engagements",
        {
          tenant: organizationId,
          owner: list.ownerId ?? null,
          due_before: instantArg(list.dueBefore) ?? null,
          page_size: list.limit ?? null,
        },
        (value) => recordsOf(value, "open_engagements").map(engagementOf),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "engagements",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
