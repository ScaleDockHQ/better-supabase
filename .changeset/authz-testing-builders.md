---
"better-supabase": minor
---

`better-supabase/testing` adds `authorizationRequest` and `sessionSnapshot`, which build the request and snapshot shapes the server builds. `testAuthorizer` also checks write requests with `source: "input"` and a `change`. `testAuthorizationProvider` checks that the token hook names one truncated marker and that a hook writing `permissions` has `sqlComplete` keys.
