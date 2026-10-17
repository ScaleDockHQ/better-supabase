import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  instantArg,
  isRecord,
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
export interface Engagement<F extends object = Record<never, never>> {
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
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
}

/** The fields of a write. On update, left out keeps the value and `null` clears it. */
export interface EngagementInput<F extends object = Record<never, never>> {
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
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** `F` types the engagements' extra columns, from the `fields` schema. */
export interface Engagements<F extends object = Record<never, never>> {
  /** Logs an engagement on the records in `subjects`, the first being its main record. */
  log(
    organizationId: string,
    input: EngagementInput<F> & {
      readonly type: string;
      readonly title: string;
    },
    subjects: readonly EngagementSubject[],
  ): AsyncResult<Engagement<F>>;
  /** Changes an engagement, and its records when `subjects` is given. */
  update(
    id: string,
    input: EngagementInput<F>,
    subjects?: readonly EngagementSubject[],
  ): AsyncResult<Engagement<F>>;
  /** Marks it done now, with an outcome, or open again with `done: false`. */
  complete(
    id: string,
    options?: { readonly done?: boolean; readonly outcome?: string },
  ): AsyncResult<Engagement<F>>;
  remove(id: string): AsyncResult<boolean>;
  /** A record's engagements, newest first (50 by default, at most 200). */
  of(
    subject: EngagementSubject,
    options?: {
      readonly types?: readonly string[];
      readonly before?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<Engagement<F>[]>;
  /** The next open engagement with a due time on a record, or `undefined`. */
  next(subject: EngagementSubject): AsyncResult<Engagement<F> | undefined>;
  /** A member's open engagements, earliest due first. Default: the caller's. */
  open(
    organizationId: string,
    options?: {
      readonly ownerId?: string;
      readonly dueBefore?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<Engagement<F>[]>;
}

export interface EngagementsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. */
  readonly schema?: string;
  /**
   * A Standard Schema for the engagements' extra columns
   * (`blocks.engagements.options.extraColumns`), keyed by column name. It
   * types and parses `fields` on reads and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Engagements<FieldsOf<S>>>>;
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
    fields: isRecord(row["fields"]) ? row["fields"] : {},
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
export function createEngagements<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: EngagementsOptions<S>): Engagements<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(
    options.fields,
    "engagement fields",
  );
  const parsed = (engagement: Engagement): AsyncResult<Engagement<F>> =>
    AsyncResult.from(() => fields.read(engagement.fields)).map((value) => ({
      ...engagement,
      fields: value,
    }));
  const parsedAll = (
    engagements: readonly Engagement[],
  ): AsyncResult<Engagement<F>[]> =>
    AsyncResult.from(async () => {
      const out: Engagement<F>[] = [];
      for (const engagement of engagements) {
        const read = await parsed(engagement);
        if (!read.ok) {
          return read;
        }
        out.push(read.data);
      }
      return ok(out);
    });
  /** The attrs of a write, with the extra fields checked first. */
  const checked = (
    input: EngagementInput<F>,
  ): AsyncResult<Record<string, unknown>> => {
    const { fields: extra, ...rest } = input;
    if (extra === undefined) {
      return AsyncResult.ok(attrsOf(rest));
    }
    return AsyncResult.from(() => fields.write({ ...extra })).map((valid) => ({
      ...attrsOf(rest),
      fields: valid,
    }));
  };
  const client: Engagements<F> = {
    log: (organizationId, input, subjects) =>
      checked(input)
        .andThen((attrs) =>
          call(
            "log_engagement",
            {
              tenant: organizationId,
              attrs,
              subjects: subjectsArg(subjects),
            },
            engagementOf,
          ),
        )
        .andThen(parsed),
    update: (id, input, subjects) =>
      checked(input)
        .andThen((attrs) =>
          call(
            "update_engagement",
            {
              engagement: id,
              attrs,
              subjects: subjects === undefined ? null : subjectsArg(subjects),
            },
            engagementOf,
          ),
        )
        .andThen(parsed),
    complete: (id, complete = {}) =>
      call(
        "complete_engagement",
        {
          engagement: id,
          done: complete.done ?? true,
          outcome: complete.outcome ?? null,
        },
        engagementOf,
      ).andThen(parsed),
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
      ).andThen(parsedAll),
    next: (subject) =>
      call(
        "next_engagement",
        { subject_type: subject.type, subject_id: subject.id },
        (value) => (value === null ? undefined : engagementOf(value)),
      ).andThen((found) =>
        found === undefined ? AsyncResult.ok(undefined) : parsed(found),
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
      ).andThen(parsedAll),
  };
  return withBlockHooks(client, options.hooks, {
    block: "engagements",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
