---
"better-supabase": minor
---

`createNext` starts the flows that email a link: `signInWithOtp`, `resetPasswordForEmail`, `signUp` and `resend` call Auth with a PKCE challenge and write the same verifier cookie as `authorizeUrl`, so `exchangeCode` signs the user in from the link's `?code=` with the default email templates. A flow started with supabase-js stores its verifier in another format that `exchangeCode` can't read. `signInWithOtp`, `resetPasswordForEmail` and `resend` return an `ActionResult<null>`; `signUp` returns `null` until the user confirms, or commits the session like `signIn` when email confirmation is off. `SignedIn` now carries `user` (the verified claims' `UserClaims`, `null` after sign-out), so an action needs no `getUser()` call after signing in.
