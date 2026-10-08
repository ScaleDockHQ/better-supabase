---
"better-supabase": patch
---

`tenantOf` also takes the client's `useAuth()` snapshot, so browser and native apps read the active tenant without parsing claims. The `optimistic` handlers type their error as `Error`, so spreading them into `useMutation` keeps `mutation.error.message` typed.
