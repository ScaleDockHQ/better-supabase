"use client";

import type { VisibleRange } from "better-supabase/blocks";
import type {
  AvailableSlotsActions,
  AvailableSlotsSnapshot,
  Bookings,
} from "better-supabase/blocks/bookings";

import { rpcTransport } from "better-supabase/blocks";
import {
  createAvailableSlotsController,
  createBookings,
} from "better-supabase/blocks/bookings";
import { useBlockEnv, useController } from "better-supabase/react";
import { useEffect, useMemo } from "react";

export interface UseAvailableSlotsOptions {
  readonly serviceId: string;
  /** The visible range, as a date picker or schedule reports it. */
  readonly range: VisibleRange;
  /** The zone slot times are shown in. Default each resource's. */
  readonly tz?: string;
  readonly resourceId?: string;
  /** A share-link token: loads and holds slots as a guest. */
  readonly token?: string;
  /** The schema the calls go to. Default `better_supabase`. */
  readonly schema?: string;
}

export interface AvailableSlotsState
  extends AvailableSlotsSnapshot, Omit<AvailableSlotsActions, "setRange"> {
  readonly client: Bookings;
}

/**
 * The open slots of a service in the visible range, for a headless date and
 * time picker or a schedule such as ReUI's.
 *
 * ```tsx
 * const slots = useAvailableSlots({ serviceId, range });
 * slots.days
 *   .get("2030-03-04")
 *   ?.map((slot) => (
 *     <button onClick={() => slots.hold(slot)}>
 *       {slot.localStart.toPlainTime().toString()}
 *     </button>
 *   ));
 * ```
 */
export function useAvailableSlots(
  options: UseAvailableSlotsOptions,
): AvailableSlotsState {
  const { supabase } = useBlockEnv();
  const { schema, serviceId, tz, resourceId, token, range } = options;

  const client = useMemo(
    () =>
      createBookings({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );

  const { controller, view } = useController(
    () =>
      createAvailableSlotsController({
        client,
        serviceId,
        range,
        ...(tz === undefined ? {} : { tz }),
        ...(resourceId === undefined ? {} : { resourceId }),
        ...(token === undefined ? {} : { token }),
      }),
    [client, serviceId, tz, resourceId, token],
  );

  const from = range.start.getTime();
  const until = range.end.getTime();
  useEffect(() => {
    controller.actions.setRange({
      start: new Date(from),
      end: new Date(until),
    });
  }, [controller, from, until]);

  return useMemo(() => ({ ...view, client }), [view, client]);
}
