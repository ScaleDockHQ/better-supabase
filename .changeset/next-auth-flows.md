---
"better-supabase": minor
---

`createNext` signs users in and out on the server for every flow that starts or ends a session. `verifyOtp` verifies an email link's `token_hash` or an emailed code, `authorizeUrl` and `exchangeCode` run OAuth with a PKCE verifier cookie (httpOnly, `SameSite=Lax`, 10 minutes, deleted on exchange), `verifyMfa` commits the `aal2` session, and `signOut` ends the session in Auth before it clears the cookies, forgets the verified session and expires the user's cache tags. `signInWithPassword` is the same as `signIn`. Each returns `redirectTo` (a same-origin `next` or the fallback) and `mfa`, plain data a Server Action can return to the client; the committed session is on `getRequestSession()` and `context()` for the rest of the request.

After a sign-in or sign-out, `getRequestSession()`, `session()`, `context()` and `cached()` return the new session for the rest of the request. Reads rebuild the request from the cookie jar, so a Server Action sees its own writes, and a render that never commits still verifies its token once. Auth errors keep their `error_code` as `code` and no longer carry Auth's message, so a form can't reveal whether an account exists. `cookieScopes` on `createNext` also expires the session cookie at old scopes on sign-out.

Doctor's BS506 warns when an env file sets `SUPABASE_URL` and a browser spelling such as `NEXT_PUBLIC_SUPABASE_URL` to different URLs, since the session cookie name comes from the URL and the server and the browser would then read different cookies. Set `auth.cookie.name` on both clients when the split is intended.
