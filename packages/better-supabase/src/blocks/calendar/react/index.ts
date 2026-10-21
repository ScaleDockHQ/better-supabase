"use client";

import { useEffect, useMemo } from "react";

import type { VisibleRange } from "../../range.ts";
import type { Calendar } from "../calendar.ts";
import type { CalendarActions, CalendarSnapshot } from "../client.ts";
import type { EventCalendarOptions } from "../event-calendar.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createCalendar } from "../calendar.ts";
import { createCalendarController } from "../client.ts";

export interface UseCalendarOptions extends EventCalendarOptions {
  readonly calendarIds: readonly string[];
  /** The visible range, as an event calendar's `onRangeChange` reports it. */
  readonly range: VisibleRange;
  /** The schema the calls go to. Default `better_supabase`. */
  readonly schema?: string;
}

export interface CalendarState
  extends CalendarSnapshot, Omit<CalendarActions, "setRange"> {
  readonly client: Calendar;
}

/**
 * The occurrences of some calendars in the visible range, typed for a headless
 * event calendar such as ReUI's Event Calendar.
 *
 * ```tsx
 * const [range, setRange] = useState({ start, end });
 * const calendar = useCalendar({ calendarIds: [id], range });
 * <EventCalendar events={calendar.events} onRangeChange={setRange} />;
 * ```
 */
export function useCalendar(options: UseCalendarOptions): CalendarState {
  const { supabase } = useBlockEnv();
  const { schema, range } = options;

  const client = useMemo(
    () =>
      createCalendar({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );

  const ids = options.calendarIds.join(",");
  const { resourceOf, readOnly } = options;

  const { controller, view } = useController(
    () =>
      createCalendarController({
        client,
        calendarIds: ids === "" ? [] : ids.split(","),
        range,
        ...(resourceOf === undefined ? {} : { resourceOf }),
        ...(readOnly === undefined ? {} : { readOnly }),
      }),
    [client, ids, resourceOf, readOnly],
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
