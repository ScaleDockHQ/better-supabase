import type { CalendarState, UseCalendarOptions } from "./index.ts";

export type { CalendarState, UseCalendarOptions } from "./index.ts";

/**
 * The `react-server` build of `useCalendar`: call `calendar.occurrences()`
 * instead.
 */
export const useCalendar: (
  options: UseCalendarOptions,
) => CalendarState = () => {
  throw new Error(
    "better-supabase: useCalendar() runs in Client Components only. In Server Components call `calendar.occurrences()` instead.",
  );
};
