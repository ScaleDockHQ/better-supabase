import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { Controller } from "../controller.ts";
import type { VisibleRange } from "../range.ts";
import type { Calendar, CalendarEventInput } from "./calendar.ts";
import type {
  EventCalendarEvent,
  EventCalendarOptions,
} from "./event-calendar.ts";
import type { CalendarOccurrence } from "./occurrences.ts";

import { temporal } from "../../core/temporal-required.ts";
import { defineController } from "../controller.ts";
import { sameRange } from "../range.ts";
import { toEventCalendarEvents } from "./event-calendar.ts";

export interface CalendarControllerOptions extends EventCalendarOptions {
  readonly client: Pick<
    Calendar,
    "occurrences" | "editOccurrence" | "editFollowing" | "cancelOccurrence"
  >;
  readonly calendarIds: readonly string[];
  /** The visible range; `setRange` changes it. */
  readonly range: VisibleRange;
}

export interface CalendarSnapshot {
  /** `undefined` until the first load. */
  readonly occurrences: readonly CalendarOccurrence[] | undefined;
  /** The occurrences as event calendar events (ReUI's `CalendarEvent` shape). */
  readonly events: readonly EventCalendarEvent<CalendarOccurrence>[];
  readonly error: DbError | undefined;
  /** True until the occurrences of the current range arrive. */
  readonly loading: boolean;
}

export interface CalendarActions {
  readonly refresh: () => Promise<void>;
  /** Saves one occurrence's change, then loads the range again. */
  readonly editOccurrence: (input: {
    occurrence: CalendarOccurrence;
    changes: CalendarEventInput;
  }) => Promise<boolean>;
  /** Saves the change for this and every later occurrence, then loads again. */
  readonly editFollowing: (input: {
    occurrence: CalendarOccurrence;
    changes: CalendarEventInput;
  }) => Promise<boolean>;
  readonly cancelOccurrence: (
    occurrence: CalendarOccurrence,
  ) => Promise<boolean>;
  /** Shows another range; the current occurrences stay until its own arrive. */
  readonly setRange: (range: VisibleRange) => void;
}

export type CalendarController = Controller<CalendarSnapshot, CalendarActions>;

/**
 * The occurrences of some calendars in the visible range, typed for a headless
 * event calendar such as ReUI's Event Calendar.
 */
export function createCalendarController(
  options: CalendarControllerOptions,
): CalendarController {
  const { client, calendarIds, resourceOf, readOnly } = options;
  let range = options.range;
  let ticket = 0;

  const eventsOf = (occurrences: readonly CalendarOccurrence[]) =>
    toEventCalendarEvents(occurrences, {
      ...(resourceOf === undefined ? {} : { resourceOf }),
      ...(readOnly === undefined ? {} : { readOnly }),
    });

  return defineController<CalendarSnapshot, CalendarActions>(
    { occurrences: undefined, events: [], error: undefined, loading: true },
    (state) => {
      const refresh = async (): Promise<void> => {
        ticket += 1;
        const request = ticket;
        state.set({ loading: true });
        const time = temporal();

        const result = await client.occurrences({
          calendarIds,
          range: {
            from: time.Instant.fromEpochMilliseconds(range.start.getTime()),
            until: time.Instant.fromEpochMilliseconds(range.end.getTime()),
          },
        });

        if (request !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? {
                occurrences: result.data,
                events: eventsOf(result.data),
                error: undefined,
                loading: false,
              }
            : { error: result.error, loading: false },
        );
      };

      const after = async (result: Result<unknown>): Promise<boolean> => {
        if (!result.ok) {
          state.set({ error: result.error });

          return false;
        }

        await refresh();

        return true;
      };

      return {
        actions: {
          refresh,
          setRange: (next) => {
            if (sameRange(range, next)) {
              return;
            }

            range = next;
            void refresh();
          },
          editOccurrence: async ({ occurrence, changes }) =>
            after(await client.editOccurrence({ occurrence, changes })),
          editFollowing: async ({ occurrence, changes }) =>
            after(await client.editFollowing({ occurrence, changes })),
          cancelOccurrence: async (occurrence) =>
            after(await client.cancelOccurrence(occurrence)),
        },
        start: () => {
          void refresh();

          return;
        },
      };
    },
  );
}
