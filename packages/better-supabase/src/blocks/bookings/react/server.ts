import type { AvailableSlotsState, UseAvailableSlotsOptions } from "./index.ts";

export type { AvailableSlotsState, UseAvailableSlotsOptions } from "./index.ts";

/** The `react-server` build of `useAvailableSlots`: call `bookings.availableSlots()` instead. */
export const useAvailableSlots: (
  options: UseAvailableSlotsOptions,
) => AvailableSlotsState = () => {
  throw new Error(
    "better-supabase: useAvailableSlots() runs in Client Components only. In Server Components call `bookings.availableSlots()` instead.",
  );
};
