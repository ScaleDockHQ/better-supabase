import type { AnnouncementsState, UseAnnouncementsOptions } from "./index.ts";

export type { AnnouncementsState, UseAnnouncementsOptions } from "./index.ts";

/** The `react-server` build of `useAnnouncements`: call `announcements.listActive()` instead. */
export const useAnnouncements: (
  options?: UseAnnouncementsOptions,
) => AnnouncementsState = () => {
  throw new Error(
    "better-supabase: useAnnouncements() runs in Client Components only. In Server Components call `announcements.listActive()` instead.",
  );
};
