import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  AuthorizationHooks,
  SubscriberPolicy,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { Notifier } from "../ports.ts";
import type {
  EnqueueOnceOptions,
  EnqueueOnceResult,
  JobHandler,
} from "../queue/types.ts";
import type { DeliveryPayload } from "./schedule.ts";

import {
  blockFields,
  readFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalRecordRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError, isDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { subjectReaders } from "../../core/subject-readers.ts";
import { temporal } from "../../core/temporal-required.ts";
import { isInstant } from "../../core/temporal.ts";
import { allowedSubscribers } from "../../realtime/subscribers.ts";
import {
  blockCall,
  instantOf,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { planReminderDeliveries } from "./schedule.ts";

/** Sends `notification` through `notifier` for a delivered reminder. */
function notifyThrough(
  options: Pick<RemindersOptions, "notifier" | "notification">,
): ((delivery: DeliveryPayload) => unknown) | undefined {
  const { notifier, notification } = options;

  if (notifier === undefined || notification === undefined) {
    return undefined;
  }

  return (delivery) =>
    notifier.send(notification, {
      recipients: delivery.userId === undefined ? [] : [delivery.userId],
      tenant: delivery.organizationId,
      key: `reminder:${delivery.reminderId}:${delivery.occurrenceAt.toString()}`,
      ...(delivery.subject === undefined ? {} : { subject: delivery.subject }),
      data: {
        reminderId: delivery.reminderId,
        occurrenceAt: delivery.occurrenceAt.toString(),
      },
    });
}

/** The queue `reminders.job` handles. */
export const REMINDER_DELIVERY_QUEUE = "reminders.deliver";

/** The payload `schedule` enqueues on `reminders.deliver`. */
export interface ReminderJobPayload {
  readonly reminderId: string;
  /** ISO text. */
  readonly occurrenceAt: string;
  readonly organizationId: string;
  readonly userId?: string;
  readonly subject?: RecordRef;
}

/**
 * The jobs queue `schedule` enqueues on: the `queue` block's client, typed by
 * shape so this block doesn't need it.
 */
export interface ReminderJobs {
  enqueueOnce(
    queue: typeof REMINDER_DELIVERY_QUEUE,
    payload: ReminderJobPayload,
    options: EnqueueOnceOptions,
  ): AsyncResult<EnqueueOnceResult>;
}

/** What `schedule` plans and when. */
export interface ReminderScheduleOptions {
  /** Default: now. */
  readonly now?: Temporal.Instant;
  /** How far ahead to enqueue deliveries, in minutes. Default 1440 (a day). */
  readonly horizonMinutes?: number;
  /**
   * How far back a missed delivery still goes out, in minutes. Default 15, so a
   * schedule run that comes late still sends what fell due since.
   */
  readonly lookbackMinutes?: number;
}

/** What one `schedule` run did. */
export interface ReminderScheduleResult {
  /** Deliveries due in the window. */
  readonly planned: number;
  /** New jobs on `reminders.deliver`. */
  readonly enqueued: number;
  /** Deliveries that already had a job. */
  readonly duplicates: number;
  /**
   * Schedule rows that couldn't be expanded: a rule kept in columns
   * (`ruleFormat: "columns"`), or an unknown time zone.
   */
  readonly skipped: number;
}

export interface RemindersOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTenantOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * Runs after `deliver` records an occurrence for the first time. Defaults to
   * sending `notification` through `notifier`.
   */
  readonly notifyDelivery?: (delivery: DeliveryPayload) => unknown;
  /** The `notifier` port: the `notifications` block, from `createBlocks`. */
  readonly notifier?: Notifier;
  /**
   * The notification type `notifier` sends for a delivered reminder, to the
   * user who set it and the reminded subject's watchers. Its data is `{
   * reminderId, occurrenceAt }`, with `occurrenceAt` as ISO text.
   */
  readonly notification?: string;
  /**
   * Checks the reminder's user before `notifyDelivery` runs; a user it leaves
   * out gets nothing, and a throw fails the delivery so the job retries.
   * Defaults to `authorization.delivery.audience`; with `authorization` but no
   * such policy, to `subjectReaders(transport)`, so a user who lost access to
   * the subject stops getting its reminders.
   */
  readonly audience?: SubscriberPolicy;
  /** `server.authorization`, for its `delivery.audience` policy. */
  readonly authorization?: Pick<AuthorizationHooks, "delivery">;
  /**
   * A Standard Schema for the extra columns of the reminders table
   * (`blocks.reminders.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /**
   * The jobs queue `schedule` enqueues deliveries on, such as the client
   * `createQueue` returns.
   */
  readonly jobs?: ReminderJobs;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Reminders<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** A saved reminder: its id and the app's extra columns. */
export interface SavedReminder<F extends object = Record<never, never>> {
  readonly id: string;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

/** One of the caller's reminders, from `list`. */
export interface ReminderEntry {
  readonly id: string;
  readonly method: string;
  /** Minutes before the occurrence; negative fires after it. */
  readonly offsetMinutes: number;
  /** A one-time reminder's own time, in place of the subject's schedule. */
  readonly remindAt?: Temporal.Instant;
}

/**
 * When a reminder fires: minutes before each occurrence of the subject's rule
 * (or its `on.<type>.at` column), or once at `at`.
 */
export type ReminderWhen = number | { readonly at: Temporal.Instant };

/**
 * `F` is the extra fields `options.fields` describes. `upsert` and `list` act
 * in the block's `tenant`.
 */
export interface Reminders<F extends object = Record<never, never>> {
  /**
   * Sets a reminder on `subject`: `offsetMinutes` before each occurrence, or
   * once at `{ at }`. `fields` fills the app's extra columns.
   */
  upsert(
    subject: RecordRef,
    when?: ReminderWhen,
    fields?: Partial<F> & Readonly<Record<string, unknown>>,
  ): AsyncResult<SavedReminder<F>>;
  /**
   * The caller's reminders on `subject`, the earliest before the occurrence
   * first.
   */
  list(subject: RecordRef): AsyncResult<readonly ReminderEntry[]>;
  /** Removes one of the caller's reminders; `false` when there was none. */
  remove(reminderId: string): AsyncResult<boolean>;
  /**
   * Service role. Records one delivery and the reminder.sent event. Resolves to
   * `false` when the occurrence was already delivered.
   */
  markSent(
    reminderId: string,
    occurrenceAt: Temporal.Instant,
  ): AsyncResult<boolean>;
  /**
   * Checks `audience`, then `markSent`, then `notifyDelivery` when this run
   * recorded the occurrence and the audience kept the user.
   */
  deliver(delivery: DeliveryPayload): AsyncResult<boolean>;
  /** The handler for the `reminders.deliver` queue. */
  readonly job: JobHandler<unknown>;
  /**
   * Service role. Reads every reminder's schedule and enqueues one
   * `reminders.deliver` job per occurrence due in the window on `jobs`, once
   * per reminder and occurrence.
   */
  schedule(
    options?: ReminderScheduleOptions,
  ): AsyncResult<ReminderScheduleResult>;
}

interface ScheduleRow {
  readonly reminder: string;
  readonly dtstart: Temporal.Instant;
  readonly tzid: string;
  readonly rrule: string | undefined;
  readonly offsetMinutes: number;
  readonly organizationId: string;
  readonly subject: RecordRef | undefined;
  readonly userId: string | undefined;
}

function scheduleRowOf(row: Readonly<Record<string, unknown>>): ScheduleRow {
  const userId = optionalText(row["user_id"]);

  return {
    reminder: textOf(row["reminder"]),
    dtstart: instantOf(row["dtstart"]),
    tzid: textOf(row["tzid"]),
    rrule: optionalText(row["rrule"]),
    offsetMinutes: Number(row["offset_minutes"]),
    organizationId: textOf(row["tenant"]),
    subject: optionalRecordRefOf(row["subject_type"], row["subject_id"]),
    userId,
  };
}

/** The rows' deliveries in the window, and how many rows had no RRULE. */
function planRows(
  rows: readonly ScheduleRow[],
  window: { readonly from: Temporal.Instant; readonly until: Temporal.Instant },
): {
  readonly planned: readonly {
    readonly row: ScheduleRow;
    readonly occurrenceAt: Temporal.Instant;
    readonly runAt: Temporal.Instant;
    readonly dedupeKey: string;
  }[];
  readonly skipped: number;
} {
  const planned = [];
  let skipped = 0;

  for (const row of rows) {
    if (row.rrule === undefined) {
      skipped += 1;
      continue;
    }

    let dtstart: Temporal.ZonedDateTime;

    try {
      dtstart = row.dtstart.toZonedDateTimeISO(row.tzid);
    } catch {
      skipped += 1;
      continue;
    }

    const deliveries = planReminderDeliveries(
      [
        {
          id: row.reminder,
          dtstart,
          rrule: row.rrule,
          offsetMinutes: row.offsetMinutes,
        },
      ],
      {
        from: window.from.toZonedDateTimeISO("UTC"),
        until: window.until.toZonedDateTimeISO("UTC"),
      },
    );

    for (const delivery of deliveries) {
      planned.push({ row, ...delivery });
    }
  }

  return { planned, skipped };
}

function deliveryOf(value: unknown): DeliveryPayload {
  if (!isRecord(value)) {
    throw new TypeError(`${REMINDER_DELIVERY_QUEUE} needs an object payload`);
  }

  const userId = optionalText(value["userId"]);
  const nested = isRecord(value["subject"]) ? value["subject"] : undefined;

  // Jobs enqueued before `subject` replaced the flat keys still carry them.
  const subject = nested
    ? optionalRecordRefOf(nested["type"], nested["id"])
    : optionalRecordRefOf(value["subjectType"], value["subjectId"]);

  return {
    reminderId: textOf(value["reminderId"]),
    occurrenceAt: isInstant(value["occurrenceAt"])
      ? value["occurrenceAt"]
      : instantOf(value["occurrenceAt"]),
    organizationId: textOf(value["organizationId"]),
    ...(userId === undefined ? {} : { userId }),
    ...(subject === undefined ? {} : { subject }),
  };
}

/** The `reminders.deliver` payload, for the queue's `queues` map. */
export const reminderJobSchema: StandardSchemaV1<ReminderJobPayload> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) => {
      try {
        const { occurrenceAt, ...rest } = deliveryOf(value);

        return { value: { ...rest, occurrenceAt: occurrenceAt.toString() } };
      } catch (error) {
        return {
          issues: [
            { message: error instanceof Error ? error.message : String(error) },
          ],
        };
      }
    },
  },
};

export function createReminders<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: RemindersOptions<S>): Reminders<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "reminder fields");
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const notifyDelivery = options.notifyDelivery ?? notifyThrough(options);

  const audience =
    options.audience ??
    options.authorization?.delivery?.audience ??
    (options.authorization === undefined
      ? undefined
      : subjectReaders(
          options.transport,
          options.schema === undefined ? {} : { schema: options.schema },
        ));

  /**
   * Whether `audience` lets the reminder's user have it, or the policy's
   * failure.
   */
  const permitted = (delivery: DeliveryPayload): AsyncResult<boolean> =>
    AsyncResult.from(async () => {
      if (audience === undefined || delivery.userId === undefined) {
        return ok(true);
      }

      const subscriber = { principal: delivery.userId, kind: "user" as const };

      const checked = await allowedSubscribers(
        audience,
        {
          type: "reminder.due",
          tenant: delivery.organizationId,
          actorId: null,
          payload: delivery,
          subject:
            delivery.subject === undefined
              ? null
              : `subjects/${delivery.subject.type}/${delivery.subject.id}`,
        },
        [subscriber],
      );

      return checked.ok
        ? ok(checked.allowed.length > 0)
        : err(
            dbError(
              "unexpected",
              `The reminder audience check failed: ${checked.cause instanceof Error ? checked.cause.message : String(checked.cause)}`,
              { hint: "REMINDER_AUDIENCE_FAILED" },
            ),
          );
    });

  const markSent: Reminders["markSent"] = (reminderId, occurrenceAt) =>
    call(
      "mark_reminder_sent",
      { reminder: reminderId, occurrence_at: occurrenceAt },
      (value) => value === true,
    );

  const deliver: Reminders["deliver"] = (delivery) =>
    (notifyDelivery === undefined
      ? AsyncResult.ok(false)
      : permitted(delivery)
    ).andThen((allowed) =>
      hooked
        .markSent(delivery.reminderId, delivery.occurrenceAt)
        .andThen(async (sent) => {
          if (sent && allowed && notifyDelivery !== undefined) {
            const outcome: unknown = await notifyDelivery(delivery);

            if (
              isRecord(outcome) &&
              outcome["ok"] === false &&
              isDbError(outcome["error"])
            ) {
              return err(outcome["error"]);
            }
          }

          return ok(sent);
        }),
    );

  const schedule: Reminders["schedule"] = (scheduleOptions = {}) =>
    AsyncResult.from(async () => {
      const jobs = options.jobs;

      if (jobs === undefined) {
        return err(
          dbError(
            "unexpected",
            "reminders.schedule needs the jobs queue: pass `jobs` to createReminders",
            { hint: "REMINDER_JOBS_MISSING" },
          ),
        );
      }

      const now = scheduleOptions.now ?? temporal().Now.instant();

      const window = {
        from: now.subtract({ minutes: scheduleOptions.lookbackMinutes ?? 15 }),
        until: now.add({ minutes: scheduleOptions.horizonMinutes ?? 1440 }),
      };

      const rows = await call("list_reminder_schedule", {}, (value) =>
        recordsOf(value, "list_reminder_schedule").map(scheduleRowOf),
      );

      if (!rows.ok) {
        return rows;
      }

      const { planned, skipped } = planRows(rows.data, window);
      let enqueued = 0;

      for (const { row, occurrenceAt, runAt, dedupeKey } of planned) {
        const job = await jobs.enqueueOnce(
          REMINDER_DELIVERY_QUEUE,
          {
            reminderId: row.reminder,
            occurrenceAt: occurrenceAt.toString(),
            organizationId: row.organizationId,
            ...(row.userId === undefined ? {} : { userId: row.userId }),
            ...(row.subject === undefined ? {} : { subject: row.subject }),
          },
          {
            dedupeKey,
            runAt: temporal().Instant.compare(runAt, now) < 0 ? now : runAt,
            context: { tenant: row.organizationId },
          },
        );

        if (!job.ok) {
          return job;
        }

        enqueued += job.data.duplicate ? 0 : 1;
      }

      return ok({
        planned: planned.length,
        enqueued,
        duplicates: planned.length - enqueued,
        skipped,
      });
    });

  const client: Reminders<F> = {
    upsert: (subject, when, values) =>
      tenant().andThen((organizationId) =>
        writeFields(fields, values, (checked) =>
          call(
            "save_reminder",
            {
              tenant: organizationId,
              subject_type: subject.type,
              subject_id: subject.id,
              ...(typeof when === "object"
                ? { offset_minutes: 0, remind_at: when.at }
                : { offset_minutes: when ?? 0 }),
              fields: checked,
            },
            (value) => {
              const row = recordOf(value, "save_reminder");

              return {
                id: textOf(row["id"]),
                fields: rowFields(row["fields"]),
              };
            },
          ),
        ).andThen((saved) => readFields(fields, saved)),
      ),
    list: (subject) =>
      tenant().andThen((organizationId) =>
        call(
          "list_my_reminders",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) =>
            recordsOf(value, "list_my_reminders").map((row) => ({
              id: textOf(row["id"]),
              method: textOf(row["method"]),
              offsetMinutes: Number(row["offsetMinutes"]),
              ...(row["remindAt"] === undefined || row["remindAt"] === null
                ? {}
                : { remindAt: instantOf(row["remindAt"]) }),
            })),
        ),
      ),
    remove: (reminderId) =>
      call(
        "delete_reminder",
        { reminder: reminderId },
        (value) => value === true,
      ),
    markSent,
    deliver,
    job: async (payload) => {
      await hooked.deliver(deliveryOf(payload)).orThrow();
    },
    schedule,
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "reminders",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
