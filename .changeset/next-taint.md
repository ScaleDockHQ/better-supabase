---
"better-supabase": minor
---

`createNext` taints the access token and the refresh token (`experimental_taintUniqueValue`) and the auth state, the server context and the `bsb.admin()` context (`experimental_taintObjectReference`), so React refuses to serialize them to a Client Component. It does nothing without `experimental.taint: true` or on a React build without the API. `createNextConfig()` turns the flag on.
