import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BookingCustomer, PlacedBooking } from "../bookings/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { ReminderWhen, SavedReminder } from "../reminders/index.ts";
import type { SchedulingParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { ok } from "../../core/result.ts";

/** What `scheduling.bookWithReminder` returns. */
export interface BookedWithReminder {
  readonly booking: PlacedBooking;
  readonly reminder: SavedReminder;
}

/** The helpers `scheduling` adds over its parts. */
export interface Scheduling {
  /**
   * Books a slot (`bookings.hold` with `confirm: true`), then sets the caller's
   * reminder on the booking: `reminder` minutes before it, or once at an
   * instant. A failed reminder returns its error and leaves the booking
   * confirmed, so retry it with `reminders.upsert`.
   */
  bookWithReminder(input: {
    serviceId: string;
    resourceId: string;
    startsAt: Temporal.Instant;
    customer?: BookingCustomer | undefined;
    reminder: ReminderWhen;
  }): AsyncResult<BookedWithReminder>;
}

/** What the `scheduling` creator receives. */
export type SchedulingOptions = BlockContext &
  CompositeOptions<SchedulingParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Scheduling>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `scheduling` helpers over the clients of its parts. */
export function createScheduling(options: SchedulingOptions): Scheduling {
  const { bookings, reminders } = options.parts;

  const client: Scheduling = {
    bookWithReminder: ({ reminder, customer, ...slot }) =>
      bookings
        .hold({
          ...slot,
          ...(customer === undefined ? {} : { customer }),
          confirm: true,
        })
        .andThen(async (booking) => {
          const saved = await reminders.upsert({
            subject: { type: "booking", id: booking.id },
            when: reminder,
          });

          return saved.ok ? ok({ booking, reminder: saved.data }) : saved;
        }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "scheduling",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
