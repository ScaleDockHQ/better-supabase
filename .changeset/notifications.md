---
"better-supabase": minor
---

Add the `notifications` SQL kit module and `better-supabase/notifications`. `notify(jsonb)` is a `security definer` sender that checks `notifications.send`, leaves out the actor and non-members, and applies subject subscriptions and per-channel preferences. `createNotifications` sends with typed data and reads, counts, marks, dismisses and resolves notifications; `deliver()` sends email, push and other channels through `NotificationChannel` implementations with leases and retries. `useNotifications` from `better-supabase/react` keeps a list current over a private Realtime topic. Existing tables work with `mode: 'adopt'`, and the topic and event names are configurable. `OrgsTransport` is now `KitTransport`, exported from both `better-supabase/orgs` and `better-supabase/notifications`.
