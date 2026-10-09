---
"better-supabase": minor
---

Add PowerSync helpers.

- `watch` keeps the object identity of unchanged rows between runs and skips `onResult` when a run returns the same result (`structuralSharing: false` turns it off).
- `createUploadConnector` replaces the hand-written PowerSync connector: it authenticates with the Supabase session, replays queued changes in batches through repositories, fails loudly for a table without a route, stops when the session is gone, and keeps refused changes in `connector.rejected`. `uploadOutcome` is the default error classification.
- `syncWithAuth` connects while a user is signed in and clears the local database on sign-out or a change of user.
- `better-supabase/powersync/react` (new subpath): `useWatch`, `useSyncStatus` and `useConflicts`.
