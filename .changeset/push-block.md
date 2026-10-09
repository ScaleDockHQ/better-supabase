---
"better-supabase": minor
---

Add the `push` SQL module and `better-supabase/blocks/push`. The module stores each user's device push tokens with RLS, behind `register_push_device` and `unregister_push_device` for the user and `push_tokens_for` and `prune_push_tokens` for the service role. The block registers Expo devices (`registerDevice`, typed structurally over `expo-notifications`), removes the token before sign-out (`unregisterOnSignOut`), sends through the Expo Push API with `fetch` only and prunes tokens Expo reports as unregistered (`expoPush`), and delivers notifications as a channel (`expoPushChannel`).
