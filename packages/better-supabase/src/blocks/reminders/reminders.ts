import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { JobHandler } from "../jobs/types.ts";
import type { DeliveryPayload } from "./schedule.ts";

import { isDbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
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
  /** `markSent`, then `notifyDelivery` when this run recorded the occurrence. */
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
  const markSent: Reminders["markSent"] = (reminderId, occurrenceAt) =>
    call(
      "mark_reminder_sent",
      { reminder: reminderId, occurrence_at: occurrenceAt },
      (value) => value === true,
    );
  const deliver: Reminders["deliver"] = (delivery) =>
    markSent(delivery.reminderId, delivery.occurrenceAt).andThen(
      async (sent) => {
        if (sent && options.notifyDelivery !== undefined) {
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
