import type { NotificationsState, UseNotificationsOptions } from "./index.ts";

export type {
  NotificationSource,
  NotificationsState,
  UseNotificationsOptions,
} from "./index.ts";

/** The `react-server` build of `useNotifications`: call `notifications.list()` instead. */
export const useNotifications: <T>(
  options: UseNotificationsOptions<T>,
) => NotificationsState<T> = () => {
  throw new Error(
    "better-supabase: useNotifications() runs in Client Components only. In Server Components call `notifications.list()` instead.",
  );
};
