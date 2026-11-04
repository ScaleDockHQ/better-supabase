---
"better-supabase": minor
---

`better-supabase/testing` gains `createFakeClient(handler)`, a supabase-js stand-in that records
each request (method, path, query, body), answers `.single()` and `.maybeSingle()` like PostgREST
(a miss is `PGRST116`) and supports `.schema()` and `.rpc()`. Test tokens still come from
`signTestJwt`. The pgTAP helpers add `tests.authenticate_as(email)` and
`tests.authenticate_as_issued(user_id, hook)`, which runs your custom access token hook for the
claims. `hook` defaults to `auth.hook.custom_access_token` from `config.toml` when `sql sync`
writes the helpers.
