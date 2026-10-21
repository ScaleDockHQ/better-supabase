import type { DbError } from "../../core/errors.ts";
import type { Controller } from "../controller.ts";
import type { VisibleRange } from "../range.ts";
import type {
  BookingCustomer,
  Bookings,
  BookingSlot,
  PlacedBooking,
} from "./bookings.ts";

import { temporal } from "../../core/temporal-required.ts";
import { defineController } from "../controller.ts";
import { sameRange } from "../range.ts";
import { slotsByDay } from "./event-calendar.ts";

export interface AvailableSlotsOptions {
  readonly client: Pick<Bookings, "availableSlots" | "hold"> & {
    readonly public: Pick<Bookings["public"], "slots" | "hold">;
  };
  readonly serviceId: string;
  /** The visible range; `setRange` changes it. */
  readonly range: VisibleRange;
  /** The zone slot times are shown in. Default each resource's. */
  readonly tz?: string;
  readonly resourceId?: string;
  /** A share-link token: loads and holds slots as a guest. */
  readonly token?: string;
}

export interface AvailableSlotsSnapshot {
  /** `undefined` until the first load. */
  readonly slots: readonly BookingSlot[] | undefined;
  /** The slots by local date (`YYYY-MM-DD`), for a day-by-day picker. */
  readonly days: ReadonlyMap<string, readonly BookingSlot[]>;
  readonly error: DbError | undefined;
  /** True until the slots of the current range arrive. */
  readonly loading: boolean;
}

export interface AvailableSlotsActions {
  readonly refresh: () => Promise<void>;
  /**
   * Holds a slot, then loads the range again. With a token, `customer` needs a
   * name and an email.
   */
  readonly hold: (
    slot: BookingSlot,
    customer?: BookingCustomer,
  ) => Promise<PlacedBooking | undefined>;
  /** Shows another range; the current slots stay until its slots arrive. */
  readonly setRange: (range: VisibleRange) => void;
}

export type AvailableSlotsController = Controller<
  AvailableSlotsSnapshot,
  AvailableSlotsActions
>;

const NO_DAYS: ReadonlyMap<string, readonly BookingSlot[]> = new Map();

/**
 * The open slots of a service in the visible range, for a headless date and
 * time picker.
 */
export function createAvailableSlotsController(
  options: AvailableSlotsOptions,
): AvailableSlotsController {
  const { client, serviceId, tz, resourceId, token } = options;
  let range = options.range;
  let ticket = 0;

  return defineController<AvailableSlotsSnapshot, AvailableSlotsActions>(
    { slots: undefined, days: NO_DAYS, error: undefined, loading: true },
    (state) => {
      const refresh = async (): Promise<void> => {
        ticket += 1;
        const request = ticket;
        state.set({ loading: true });
        const time = temporal();

        const span = {
          from: time.Instant.fromEpochMilliseconds(range.start.getTime()),
          until: time.Instant.fromEpochMilliseconds(range.end.getTime()),
        };

        const result =
          token === undefined
            ? await client.availableSlots(serviceId, span, {
                ...(tz === undefined ? {} : { tz }),
                ...(resourceId === undefined ? {} : { resourceId }),
              })
            : await client.public.slots(
                token,
                span,
                tz === undefined ? {} : { tz },
              );

        if (request !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? {
                slots: result.data,
                days: slotsByDay(result.data),
                error: undefined,
                loading: false,
              }
            : { error: result.error, loading: false },
        );
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
          hold: async (slot, customer) => {
            const result =
              token === undefined
                ? await client.hold(
                    serviceId,
                    slot.resourceId,
                    slot.startsAt,
                    customer,
                  )
                : await client.public.hold(
                    token,
                    slot.resourceId,
                    slot.startsAt,
                    {
                      ...customer,
                      name: customer?.name ?? "",
                      email: customer?.email ?? "",
                    },
                  );

            if (!result.ok) {
              state.set({ error: result.error });

              return;
            }

            await refresh();

            return result.data;
          },
        },
        start: () => {
          void refresh();

          return;
        },
      };
    },
  );
}
