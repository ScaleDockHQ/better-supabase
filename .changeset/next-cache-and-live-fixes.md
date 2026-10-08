---
"better-supabase": patch
---

Fixes in the Next.js, React and live-query entries:

- `clearOnUserChange` (and so `BetterSupabaseProvider` with `queryClient`) also resets better-supabase queries when the same user's token changes tenant, role or assurance level, so an organization switch never shows the previous organization's rows. A token refresh that changes only the time claims keeps the snapshot, so it no longer re-renders every hook.
- The live hooks keep the spec they started with across re-renders, refetch after the channel rejoins (including after an `<Activity>` hides and shows them), and count again when a `liveCount` seed's `at` is more than a second old.
- `sessionStale()` never goes below 30 seconds, the shortest time the Next.js client router keeps a prefetched entry.
- Reads tagged for every tenant (`{ tenant: "*" }`) also carry the table's tag, so a mutation in one tenant drops them.
- The proxy hands event sink sends it started to `after()`.
- `better-supabase/next` imports `next/navigation` by its bare specifier. With the `.js` suffix, Next.js resolved the client build in route handlers, and `next build` failed for any route that imported `better-supabase/next`.
