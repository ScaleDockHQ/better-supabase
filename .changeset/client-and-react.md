---
"better-supabase": minor
---

`better-supabase/vue`, `/solid` and `/svelte` bind the browser client with the features of `better-supabase/react`, and new hooks and query helpers cover forms, uploads and optimistic updates.

- `useAction` and `useActionForm` call a `bs.action()` and track `pending`, `data`, `error` and `fieldErrors`. `better-supabase/react` adds `usePresence`, `useSignIn`, `useSignOut`, `useDebouncedSearch`, `useSignedUrl` and `useUpload`, and `upload()` takes `onProgress`.
- `better-supabase/query` adds `optimistic` with rollback, `{ maxPages }` for infinite queries and `escapeLike`, and `createQueries` takes a `scope`. `better-supabase/tanstack-db` adds `collectionOptions`.
- `clearOnUserChange` also resets queries when the token changes tenant, role or assurance level. `bindClient` returns `dispose()`, and `liveQuery` rejoins a failed channel with backoff.
