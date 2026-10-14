"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { Result } from "../../../core/result.ts";
import type { Calendar, CalendarEventInput } from "../calendar.ts";
import type {
  EventCalendarEvent,
  EventCalendarOptions,
} from "../event-calendar.ts";
import type { CalendarOccurrence } from "../occurrences.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { temporal } from "../../../core/temporal-required.ts";
import { useSupabase } from "../../../react/hooks.ts";
import { createCalendar } from "../calendar.ts";
import { toEventCalendarEvents } from "../event-calendar.ts";

export interface UseCalendarOptions extends EventCalendarOptions {
  readonly calendarIds: readonly string[];
  /** The visible range, as an event calendar's `onRangeChange` reports it. */
  readonly range: { readonly start: Date; readonly end: Date };
  /** The schema the calls go to. Default `better_supabase`. */
  readonly schema?: string;
}

export interface CalendarState {
  /** `undefined` until the first load. */
  readonly occurrences: readonly CalendarOccurrence[] | undefined;
  /** The occurrences as event calendar events (ReUI's `CalendarEvent` shape). */
  readonly events: readonly EventCalendarEvent<CalendarOccurrence>[];
  readonly error: DbError | undefined;
  readonly loading: boolean;
  readonly refresh: () => Promise<void>;
  /** Saves one occurrence's change, then loads the range again. */
  readonly editOccurrence: (
    occurrence: CalendarOccurrence,
    changes: CalendarEventInput,
  ) => Promise<boolean>;
  /** Saves the change for this and every later occurrence, then loads again. */
  readonly editFollowing: (
    occurrence: CalendarOccurrence,
    changes: CalendarEventInput,
  ) => Promise<boolean>;
  readonly cancelOccurrence: (
    occurrence: CalendarOccurrence,
  ) => Promise<boolean>;
  readonly client: Calendar;
}

/**
 * The occurrences of some calendars in the visible range, typed for a
 * headless event calendar such as ReUI's Event Calendar.
 *
 * ```tsx
 * const [range, setRange] = useState({ start, end });
 * const calendar = useCalendar({ calendarIds: [id], range });
 * <EventCalendar events={calendar.events} onRangeChange={setRange} />
 * ```
 */
export function useCalendar(options: UseCalendarOptions): CalendarState {
  const supabase = useSupabase();
  const schema = options.schema;
  const client = useMemo(
    () =>
      createCalendar({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const ids = options.calendarIds.join(",");
  const from = options.range.start.getTime();
  const until = options.range.end.getTime();
  const [occurrences, setOccurrences] = useState<
    readonly CalendarOccurrence[] | undefined
  >(undefined);
  const [error, setError] = useState<DbError | undefined>(undefined);
  const key = `${ids}|${from}|${until}`;
  const [settled, setSettled] = useState<string | undefined>(undefined);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    const time = temporal();
    return client.occurrences(ids === "" ? [] : ids.split(","), {
      from: time.Instant.fromEpochMilliseconds(from),
      until: time.Instant.fromEpochMilliseconds(until),
    });
  }, [client, ids, from, until]);

  const apply = useCallback(
    (result: Result<CalendarOccurrence[]>, loaded: string) => {
      if (result.ok) {
        setOccurrences(result.data);
        setError(undefined);
      } else {
        setError(result.error);
      }
      setSettled(loaded);
    },
    [],
  );

  const refresh = useCallback(async () => {
    setRefreshing(true);
    apply(await load(), key);
    setRefreshing(false);
  }, [load, apply, key]);

  const after = useCallback(
    async (result: Result<unknown>) => {
      if (!result.ok) {
        setError(result.error);
        return false;
      }
      await refresh();
      return true;
    },
    [refresh],
  );

  useEffect(() => {
    let active = true;
    void load().then((result) => {
      if (active) apply(result, key);
    });
    return () => {
      active = false;
    };
  }, [load, apply, key]);

  const loading = refreshing || settled !== key;

  const { resourceOf, readOnly } = options;
  const events = useMemo(
    () =>
      toEventCalendarEvents(occurrences ?? [], {
        ...(resourceOf === undefined ? {} : { resourceOf }),
        ...(readOnly === undefined ? {} : { readOnly }),
      }),
    [occurrences, resourceOf, readOnly],
  );

  return {
    occurrences,
    events,
    error,
    loading,
    refresh,
    editOccurrence: async (occurrence, changes) =>
      after(await client.editOccurrence(occurrence, changes)),
    editFollowing: async (occurrence, changes) =>
      after(await client.editFollowing(occurrence, changes)),
    cancelOccurrence: async (occurrence) =>
      after(await client.cancelOccurrence(occurrence)),
    client,
  };
}
