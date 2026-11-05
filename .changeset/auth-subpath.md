---
"better-supabase": minor
---

Adds the `better-supabase/auth` subpath. It exports `authErrorKind` and the `AuthErrorKind` type, so an app can classify an auth-js error (`"retryable"`, `"session-missing"`, `"invalid-credentials"`, `"rate-limited"`, `"banned"` or `"unknown"`) without importing the server entry. The docs showed an import from `better-supabase`, which never exported it.
