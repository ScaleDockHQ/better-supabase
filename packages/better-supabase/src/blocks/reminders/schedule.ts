import type { SubjectRef } from "../../schema/types.ts";
import type { ExpandInput } from "./rrule.ts";

import { temporal } from "../../core/temporal-required.ts";
import { expandRule } from "./rrule.ts";

export interface ReminderPlanInput {
  readonly id: string;
  readonly dtstart: Temporal.ZonedDateTime;
  readonly rrule?: string;
  readonly columns?: ExpandInput["columns"];
  readonly offsetMinutes: number;
}

export interface PlannedDelivery {
  readonly reminderId: string;
  readonly occurrenceAt: string;
  readonly runAt: Temporal.Instant;
  /** One job per reminder and occurrence. Pass this to `enqueueOnce`. */
  readonly dedupeKey: string;
}

export interface DeliveryPayload {
  readonly reminderId: string;
  readonly occurrenceAt: string;
  readonly organizationId: string;
  /** Who set the reminder; `createBlocks` notifies them. */
  readonly userId?: string;
  /**
   * The reminded subject, from `list_reminder_schedule`; its watchers are
   * notified too.
   */
  readonly subject?: SubjectRef;
}

/**
 * Expands each rule between `from` and `until` and returns one delivery per
 * occurrence, shifted earlier by `offsetMinutes`. The caller enqueues each row
 * as a delayed `reminders.deliver` job with `dedupeKey`.
 */
export function planReminderDeliveries(
  items: readonly ReminderPlanInput[],
  window: {
    readonly from: Temporal.ZonedDateTime;
    readonly until: Temporal.ZonedDateTime;
  },
): readonly PlannedDelivery[] {
  const time = temporal();
  const planned: PlannedDelivery[] = [];

  for (const item of items) {
    const occurrences = expandRule({
      dtstart: item.dtstart,
      ...(item.rrule === undefined ? {} : { rrule: item.rrule }),
      ...(item.columns === undefined ? {} : { columns: item.columns }),
      limit: 366,
    });

    for (const occurrence of occurrences) {
      const runAt = occurrence.subtract({ minutes: item.offsetMinutes });

      if (time.ZonedDateTime.compare(runAt, window.from) < 0) {
        continue;
      }

      if (time.ZonedDateTime.compare(runAt, window.until) > 0) {
        continue;
      }

      const occurrenceAt = occurrence.toInstant().toString();
      planned.push({
        reminderId: item.id,
        occurrenceAt,
        runAt: runAt.toInstant(),
        dedupeKey: `${item.id}:${occurrenceAt}`,
      });
    }
  }

  return planned;
}

/**
 * Records the delivery, then notifies. A second run of the same occurrence is a
 * no-op in SQL.
 */
export async function deliverReminder(
  payload: DeliveryPayload,
  effects: {
    readonly markSent: (
      reminderId: string,
      occurrenceAt: string,
    ) => Promise<void>;
    readonly notify: (payload: DeliveryPayload) => Promise<void>;
  },
): Promise<void> {
  await effects.markSent(payload.reminderId, payload.occurrenceAt);
  await effects.notify(payload);
}
