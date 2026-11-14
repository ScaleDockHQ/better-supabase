---
"better-supabase": minor
---

`supabaseJwtAuth` from `better-supabase/eve` is an eve route `AuthFn` for MCP clients and other agents that send a Supabase access token as `Authorization: Bearer`. It verifies the token locally against the project's keys, so a valid token costs no Auth server call, and it never reads the session cookie. A request without a bearer token falls through to the next entry; an invalid token gets a 401 with `WWW-Authenticate: Bearer error="invalid_token"` and never reaches a later `none()`. It declares the `Bearer` challenge, so `oauthResource` and eve's own 401 advertise it. `EveAuthRejection` takes response headers as a third argument.
