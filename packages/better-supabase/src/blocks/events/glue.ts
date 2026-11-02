import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BookingCustomer, PlacedBooking } from "../bookings/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { IssuedPass, PassInput } from "../passes/index.ts";
import type { EventsParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `events.sellTicket` returns. */
export interface SoldTicket {
  readonly booking: PlacedBooking;
  readonly pass: IssuedPass;
}

/** The helpers `events` adds over its parts. */
export interface Events {
  /**
   * Books the place (`bookings.hold` with `confirm: true`), then issues the
   * ticket for the booking (`passes.issue`), holder name and email taken from
   * `customer`. A failed pass returns its error and leaves the booking
   * confirmed, so retry it with `passes.issue` on `{ bookingId }`.
   */
  sellTicket(input: {
    serviceId: string;
    resourceId: string;
    startsAt: Temporal.Instant;
    customer?: BookingCustomer | undefined;
    pass?: Omit<PassInput, "bookingId"> | undefined;
  }): AsyncResult<SoldTicket>;
}

/** What the `events` creator receives. */
export type EventsOptions = BlockContext &
  CompositeOptions<EventsParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Events>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `events` helpers over the clients of its parts. */
export function createEvents(options: EventsOptions): Events {
  const { bookings, passes } = options.parts;

  const client: Events = {
    sellTicket: ({ customer, pass, ...slot }) =>
      Async.from(async () => {
        const booking = await bookings.hold({
          ...slot,
          ...(customer === undefined ? {} : { customer }),
          confirm: true,
        });

        if (!booking.ok) {
          return booking;
        }

        const issued = await passes.issue({
          ...(customer?.name === undefined
            ? {}
            : { holderName: customer.name }),
          ...(customer?.email === undefined
            ? {}
            : { holderEmail: customer.email }),
          ...pass,
          bookingId: booking.data.id,
        });

        return issued.ok
          ? ok({ booking: booking.data, pass: issued.data })
          : issued;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "events",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
