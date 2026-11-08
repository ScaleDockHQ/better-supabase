import type { EventSink } from "../../events/cloud-event.ts";
import type { TaskRecurrence, Tasks } from "./tasks.ts";

import { expandRule } from "../../core/recurrence.ts";
import { temporal } from "../../core/temporal-required.ts";
import { eventTypeOf } from "../../events/cloud-event.ts";
import { isRecord, optionalText } from "../shared.ts";

/** How far ahead `nextTaskOccurrence` looks for the next occurrence. */
const HORIZON_DAYS = 366 * 5;

/**
 * The first occurrence of `rule` after `after`, or `undefined` when the rule
 * has ended (COUNT or UNTIL) or has none in the next five years.
 */
export function nextTaskOccurrence(
  rule: TaskRecurrence,
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

export interface TaskRecurrenceSinkOptions {
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
 * `outbox.relay('tasks', taskRecurrenceSink(tasks))`. Build `tasks` with a
 * service transport. The next item is due at the rule's first occurrence after
 * the completed item's due date (or now), and `repeat` runs once per item, so a
 * redelivered event changes nothing.
 */
export function taskRecurrenceSink(
  tasks: Pick<Tasks, "get" | "repeat">,
  options: TaskRecurrenceSinkOptions = {},
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

        const item = await tasks.get(id);

        if (!item.ok) {
          throw new Error(
            `taskRecurrenceSink: reading ${id} failed: ${item.error.message}`,
          );
        }

        const rule = item.data?.recurrence;

        if (rule === undefined) {
          continue;
        }

        const next = nextTaskOccurrence(rule, item.data?.dueAt ?? now());

        if (next === undefined) {
          continue;
        }

        const repeated = await tasks.repeat({ taskId: id, dueAt: next });

        if (!repeated.ok) {
          throw new Error(
            `taskRecurrenceSink: repeating ${id} failed: ${repeated.error.message}`,
          );
        }
      }
    },
  };
}
