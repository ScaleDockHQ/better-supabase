---
"better-supabase": minor
---

`better-supabase/testing` gets `createFakePostgrest`, a `fetch` that answers PostgREST requests from a handler so the real supabase-js client runs without a stack, and `asSignedInUser`, a test user that signs in through the stack's Auth and takes its claims from the token. The pgTAP module adds `tests.act_as(role, user_id, claims)` and `tests.visible_row_count(relation, filter)`; run `better-supabase upgrade` to rewrite the file.
