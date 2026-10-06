---
"better-supabase": minor
---

`useBroadcast` works without `<BetterSupabaseProvider>`: pass a supabase-js client as `client` (and `queryClient` for `invalidate`), and the hook follows that client's auth state to resubscribe when the user changes.
