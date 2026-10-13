import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";

import { blockCall, recordOf, textOf } from "../shared.ts";

export interface RemindersOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Reminders {
  save(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    offsetMinutes?: number,
  ): AsyncResult<{ readonly id: string }>;
  /** Service role. Records one delivery and the reminder.sent event. */
  markSent(reminderId: string, occurrenceAt: string): AsyncResult<boolean>;
}

export function createReminders(options: RemindersOptions): Reminders {
  const call = blockCall(options.transport, options.schema, options.mappers);
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
    markSent: (reminderId, occurrenceAt) =>
      call(
        "mark_reminder_sent",
        { reminder: reminderId, occurrence_at: occurrenceAt },
        (value) => value === true,
      ),
  };
}
