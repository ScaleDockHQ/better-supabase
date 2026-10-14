"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { Result } from "../../../core/result.ts";
import type {
  BookingCustomer,
  Bookings,
  BookingSlot,
  PlacedBooking,
} from "../bookings.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { temporal } from "../../../core/temporal-required.ts";
import { useSupabase } from "../../../react/hooks.ts";
import { createBookings } from "../bookings.ts";
import { slotsByDay } from "../event-calendar.ts";

export interface UseAvailableSlotsOptions {
  readonly serviceId: string;
  /** The visible range, as a date picker or schedule reports it. */
  readonly range: { readonly start: Date; readonly end: Date };
  /** The zone slot times are shown in. Default each resource's. */
  readonly tz?: string;
  readonly resourceId?: string;
  /** A share-link token: loads and holds slots as a guest. */
  readonly token?: string;
  /** The schema the calls go to. Default `better_supabase`. */
  readonly schema?: string;
}

export interface AvailableSlotsState {
  /** `undefined` until the first load. */
  readonly slots: readonly BookingSlot[] | undefined;
  /** The slots by local date (`YYYY-MM-DD`), for a day-by-day picker. */
  readonly days: ReadonlyMap<string, readonly BookingSlot[]>;
  readonly error: DbError | undefined;
  readonly loading: boolean;
  readonly refresh: () => Promise<void>;
  /** Holds a slot, then loads the range again. With a token, `customer` needs a name and an email. */
  readonly hold: (
    slot: BookingSlot,
    customer?: BookingCustomer,
  ) => Promise<PlacedBooking | undefined>;
  readonly client: Bookings;
}

/**
 * The open slots of a service in the visible range, for a headless date and
 * time picker or a schedule such as ReUI's.
 *
 * ```tsx
 * const slots = useAvailableSlots({ serviceId, range });
 * slots.days.get("2030-03-04")?.map((slot) => (
 *   <button onClick={() => slots.hold(slot)}>{slot.localStart.toPlainTime().toString()}</button>
 * ));
 * ```
 */
export function useAvailableSlots(
  options: UseAvailableSlotsOptions,
): AvailableSlotsState {
  const supabase = useSupabase();
  const { schema, serviceId, tz, resourceId, token } = options;
  const client = useMemo(
    () =>
      createBookings({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const from = options.range.start.getTime();
  const until = options.range.end.getTime();
  const [slots, setSlots] = useState<readonly BookingSlot[] | undefined>(
    undefined,
  );
  const [error, setError] = useState<DbError | undefined>(undefined);
  const key = `${serviceId}|${from}|${until}|${tz ?? ""}|${resourceId ?? ""}|${token ?? ""}`;
  const [settled, setSettled] = useState<string | undefined>(undefined);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    const time = temporal();
    const range = {
      from: time.Instant.fromEpochMilliseconds(from),
      until: time.Instant.fromEpochMilliseconds(until),
    };
    if (token !== undefined) {
      return client.public.slots(token, range, tz === undefined ? {} : { tz });
    }
    return client.availableSlots(serviceId, range, {
      ...(tz === undefined ? {} : { tz }),
      ...(resourceId === undefined ? {} : { resourceId }),
    });
  }, [client, serviceId, from, until, tz, resourceId, token]);

  const apply = useCallback((result: Result<BookingSlot[]>, loaded: string) => {
    if (result.ok) {
      setSlots(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
    setSettled(loaded);
  }, []);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    apply(await load(), key);
    setRefreshing(false);
  }, [load, apply, key]);

  useEffect(() => {
    let active = true;
    void load().then((result) => {
      if (active) apply(result, key);
    });
    return () => {
      active = false;
    };
  }, [load, apply, key]);

  const days = useMemo(() => slotsByDay(slots ?? []), [slots]);

  return {
    slots,
    days,
    error,
    loading: refreshing || settled !== key,
    refresh,
    hold: async (slot, customer) => {
      const result =
        token === undefined
          ? await client.hold(
              serviceId,
              slot.resourceId,
              slot.startsAt,
              customer,
            )
          : await client.public.hold(token, slot.resourceId, slot.startsAt, {
              ...customer,
              name: customer?.name ?? "",
              email: customer?.email ?? "",
            });
      if (!result.ok) {
        setError(result.error);
        return;
      }
      await refresh();
      return result.data;
    },
    client,
  };
}
