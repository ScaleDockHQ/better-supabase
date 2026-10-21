import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  AuthorizationHooks,
  SubscriberPolicy,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { JobHandler } from "../jobs/types.ts";
import type { Notifier } from "../ports.ts";
import type { DeliveryPayload } from "./schedule.ts";

import {
  blockFields,
  readFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError, isDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { subjectReaders } from "../../core/subject-readers.ts";
import { allowedSubscribers } from "../../realtime/subscribers.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

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
      key: `reminder:${delivery.reminderId}:${delivery.occurrenceAt}`,
      ...(delivery.subjectType === undefined || delivery.subjectId === undefined
        ? {}
        : { subject: { type: delivery.subjectType, id: delivery.subjectId } }),
      data: {
        reminderId: delivery.reminderId,
        occurrenceAt: delivery.occurrenceAt,
      },
    });
}

/** The queue `reminders.job` handles. */
export const REMINDER_DELIVERY_QUEUE = "reminders.deliver";

export interface RemindersOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> {
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
   * reminderId, occurrenceAt }`.
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
}

export interface Reminders<F extends object = Record<never, never>> {
  /** Sets a reminder on a subject; `fields` fills the app's extra columns. */
  save(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    offsetMinutes?: number,
    fields?: Partial<F> & Readonly<Record<string, unknown>>,
  ): AsyncResult<SavedReminder<F>>;
  /**
   * The caller's reminders on a subject, the earliest before the occurrence
   * first.
   */
  list(
    organizationId: string,
    subjectType: string,
    subjectId: string,
  ): AsyncResult<readonly ReminderEntry[]>;
  /** Removes one of the caller's reminders; `false` when there was none. */
  remove(reminderId: string): AsyncResult<boolean>;
  /**
   * Service role. Records one delivery and the reminder.sent event. Resolves to
   * `false` when the occurrence was already delivered.
   */
  markSent(reminderId: string, occurrenceAt: string): AsyncResult<boolean>;
  /**
   * Checks `audience`, then `markSent`, then `notifyDelivery` when this run
   * recorded the occurrence and the audience kept the user.
   */
  deliver(delivery: DeliveryPayload): AsyncResult<boolean>;
  /** The handler for the `reminders.deliver` queue. */
  readonly job: JobHandler<unknown>;
}

function deliveryOf(value: unknown): DeliveryPayload {
  if (!isRecord(value)) {
    throw new TypeError(`${REMINDER_DELIVERY_QUEUE} needs an object payload`);
  }

  const userId = optionalText(value["userId"]);
  const subjectType = optionalText(value["subjectType"]);
  const subjectId = optionalText(value["subjectId"]);

  return {
    reminderId: textOf(value["reminderId"]),
    occurrenceAt: textOf(value["occurrenceAt"]),
    organizationId: textOf(value["organizationId"]),
    ...(userId === undefined ? {} : { userId }),
    ...(subjectType === undefined ? {} : { subjectType }),
    ...(subjectId === undefined ? {} : { subjectId }),
  };
}

export function createReminders<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: RemindersOptions<S>): Reminders<FieldsOf<S>> {
  type F = FieldsOf<S>;

  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "reminder fields");
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
            delivery.subjectType === undefined ||
            delivery.subjectId === undefined
              ? null
              : `subjects/${delivery.subjectType}/${delivery.subjectId}`,
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

  const client: Reminders<F> = {
    save: (organizationId, subjectType, subjectId, offsetMinutes, values) =>
      writeFields(fields, values, (checked) =>
        call(
          "save_reminder",
          {
            tenant: organizationId,
            subject_type: subjectType,
            subject_id: subjectId,
            offset_minutes: offsetMinutes ?? 0,
            fields: checked,
          },
          (value) => {
            const row = recordOf(value, "save_reminder");

            return { id: textOf(row["id"]), fields: rowFields(row["fields"]) };
          },
        ),
      ).andThen((saved) => readFields(fields, saved)),
    list: (organizationId, subjectType, subjectId) =>
      call(
        "list_my_reminders",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
        },
        (value) =>
          recordsOf(value, "list_my_reminders").map((row) => ({
            id: textOf(row["id"]),
            method: textOf(row["method"]),
            offsetMinutes: Number(row["offsetMinutes"]),
          })),
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
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "reminders",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
