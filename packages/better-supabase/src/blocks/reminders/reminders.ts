import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  AuthorizationHooks,
  SubscriberPolicy,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { JobHandler } from "../jobs/types.ts";
import type { DeliveryPayload } from "./schedule.ts";

import { dbError, isDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { subjectReaders } from "../../core/subject-readers.ts";
import { allowedSubscribers } from "../../realtime/subscribers.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";

/** The queue `reminders.job` handles. */
export const REMINDER_DELIVERY_QUEUE = "reminders.deliver";

export interface RemindersOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * Runs after `deliver` records an occurrence for the first time. Set by
   * `createBlocks` when it also builds `notifications` and has a
   * `reminderNotification` type.
   */
  readonly notifyDelivery?: (delivery: DeliveryPayload) => unknown;
  /**
   * Checks the reminder's user before `notifyDelivery` runs; a user it
   * leaves out gets nothing, and a throw fails the delivery so the job
   * retries. Defaults to `authorization.delivery.audience`; with
   * `authorization` but no such policy, to `subjectReaders(transport)`, so
   * a user who lost access to the subject stops getting its reminders.
   */
  readonly audience?: SubscriberPolicy;
  /** `server.authorization`, for its `delivery.audience` policy. */
  readonly authorization?: Pick<AuthorizationHooks, "delivery">;
}

export interface Reminders {
  save(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    offsetMinutes?: number,
  ): AsyncResult<{ readonly id: string }>;
  /**
   * Service role. Records one delivery and the reminder.sent event.
   * Resolves to `false` when the occurrence was already delivered.
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

export function createReminders(options: RemindersOptions): Reminders {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const audience =
    options.audience ??
    options.authorization?.delivery?.audience ??
    (options.authorization === undefined
      ? undefined
      : subjectReaders(
          options.transport,
          options.schema === undefined ? {} : { schema: options.schema },
        ));
  /** Whether `audience` lets the reminder's user have it, or the policy's failure. */
  const permitted = (delivery: DeliveryPayload): AsyncResult<boolean> =>
    AsyncResult.from(async () => {
      if (audience === undefined || delivery.userId === undefined)
        return ok(true);
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
    (options.notifyDelivery === undefined
      ? AsyncResult.ok(false)
      : permitted(delivery)
    ).andThen((allowed) =>
      markSent(delivery.reminderId, delivery.occurrenceAt).andThen(
        async (sent) => {
          if (sent && allowed && options.notifyDelivery !== undefined) {
            const outcome: unknown = await options.notifyDelivery(delivery);
            if (
              isRecord(outcome) &&
              outcome["ok"] === false &&
              isDbError(outcome["error"])
            ) {
              return err(outcome["error"]);
            }
          }
          return ok(sent);
        },
      ),
    );
  return {
    save: (organizationId, subjectType, subjectId, offsetMinutes) =>
      call(
        "save_reminder",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
          offset_minutes: offsetMinutes ?? 0,
        },
        (value) => ({ id: textOf(recordOf(value, "save_reminder")["id"]) }),
      ),
    markSent,
    deliver,
    job: async (payload) => {
      await deliver(deliveryOf(payload)).orThrow();
    },
  };
}
