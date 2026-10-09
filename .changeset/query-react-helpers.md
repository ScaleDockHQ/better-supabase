---
"better-supabase": minor
---

Add query and React helpers that remove common boilerplate.

- `better-supabase/query`: `optimistic`, `optimistic.create`, `optimistic.update` and `optimistic.remove` rewrite cached lists before a mutation and roll them back when it fails. `infinite` and `infinitePages` take `{ maxPages }`, and `infinitePages` sets `getPreviousPageParam`. Writes that return a full row seed that row's `findById` entry. `invalidateTables` finds queries through a table index instead of scanning the cache. `escapeLike` is exported.
- `better-supabase/react`: `usePresence`, `useSignIn`, `useSignOut`, `useDebouncedSearch`, `useSignedUrl` and `useUpload`.
- Storage: `upload()` takes `onProgress`. Where `XMLHttpRequest` exists, the body goes to a signed upload URL so progress events arrive and `signal` cancels the request.
