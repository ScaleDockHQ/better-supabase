---
"better-supabase": patch
---

The `notification-bell` recipe reads the unread count in the browser: it calls the `notification_counts` function on the `api` schema through `useBlockEnv().supabase`, so the bell no longer needs the `loadNotificationCounts` Server Action.
