---
"better-supabase": minor
---

`createNext` signs users in and out on the server for every flow that starts or ends a session. `verifyOtp` verifies an email link's `token_hash` or an emailed code, `authorizeUrl` and `exchangeCode` run OAuth with a PKCE verifier cookie (httpOnly, `SameSite=Lax`, 10 minutes, deleted on exchange), `verifyMfa` commits the `aal2` session, and `signOut` ends the session in Auth before it clears the cookies, forgets the verified session and expires the user's cache tags. `signInWithPassword` is the same as `signIn`. Each returns `redirectTo` (a same-origin `next` or the fallback), `mfa` and the committed `session`, which `contextFromSession` turns into the landing context.

After a sign-in or sign-out, `getRequestSession()`, `session()`, `context()` and `cached()` return the new session for the rest of the request. Reads rebuild the request from the cookie jar, so a Server Action sees its own writes, and a render that never commits still verifies its token once. Auth errors keep their `error_code` as `code` and no longer carry Auth's message, so a form can't reveal whether an account exists. `cookieScopes` on `createNext` also expires the session cookie at old scopes on sign-out.

`loadEnv()` and `parseEnv()` report an issue when two URL spellings, such as `SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_URL`, hold different URLs, since the server and the browser would then read different session cookies.
