import type { EventSink } from "../../events/cloud-event.ts";
import type { WorkItemRecurrence, Tasks } from "./tasks.ts";

import { temporal } from "../../core/temporal-required.ts";
import { eventTypeOf } from "../../events/cloud-event.ts";
import { expandRule } from "../reminders/rrule.ts";
import { isRecord, optionalText } from "../shared.ts";

/** How far ahead `nextWorkItemOccurrence` looks for the next occurrence. */
const HORIZON_DAYS = 366 * 5;

/**
 * The first occurrence of `rule` after `after`, or `undefined` when the rule
 * has ended (COUNT or UNTIL) or has none in the next five years.
 */
export function nextWorkItemOccurrence(
  rule: WorkItemRecurrence,
  after: Temporal.Instant,
): Temporal.Instant | undefined {
  const [next] = expandRule({
    dtstart: rule.dtstart.toZonedDateTimeISO(rule.tzid),
    rrule: rule.rrule,
    window: {
      from: after.add({ milliseconds: 1 }),
      until: after.add({ hours: 24 * HORIZON_DAYS }),
    },
    limit: 1,
  });

  return next?.toInstant();
}

export interface WorkItemRecurrenceSinkOptions {
  /**
   * The closed event's type without `typePrefix`, after `blocks.tasks.names`
   * (`task.closed`). Default `task.closed`.
   */
  readonly type?: string;
  /** Stripped from each event type. Defaults to `dev.better-supabase`. */
  readonly typePrefix?: string;
  /** The current time, for an item without a due date. */
  readonly now?: () => Temporal.Instant;
}

/**
 * An outbox sink that creates the next item when a repeating one is completed:
 * `outbox.relay('tasks', workItemRecurrenceSink(workItems))`. Build `workItems`
 * with a service transport. The next item is due at the rule's first occurrence
 * after the completed item's due date (or now), and `repeat` runs once per
 * item, so a redelivered event changes nothing.
 */
export function workItemRecurrenceSink(
  workItems: Pick<Tasks, "get" | "repeat">,
  options: WorkItemRecurrenceSinkOptions = {},
): EventSink {
  const type = options.type ?? "task.closed";
  const now = options.now ?? (() => temporal().Now.instant());

  return {
    async send(events) {
      for (const event of events) {
        if (
          eventTypeOf(event, options.typePrefix) !== type ||
          !isRecord(event.data) ||
          event.data["state"] !== "completed"
        ) {
          continue;
        }

        const id = optionalText(event.data["subjectId"]);

        if (id === undefined) {
          continue;
        }

        const item = await workItems.get(id);

        if (!item.ok) {
          throw new Error(
            `workItemRecurrenceSink: reading ${id} failed: ${item.error.message}`,
          );
        }

        const rule = item.data?.recurrence;

        if (rule === undefined) {
          continue;
        }

        const next = nextWorkItemOccurrence(rule, item.data?.dueAt ?? now());

        if (next === undefined) {
          continue;
        }

        const repeated = await workItems.repeat({
          workItemId: id,
          dueAt: next,
        });

        if (!repeated.ok) {
          throw new Error(
            `workItemRecurrenceSink: repeating ${id} failed: ${repeated.error.message}`,
          );
        }
      }
    },
  };
}
