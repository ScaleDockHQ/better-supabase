---
"better-supabase": minor
---

Breaking: the Next.js sign-in flows (`signInWithPassword`, `verifyOtp`,
`signInWithOAuth`, `exchangeCodeForSession`, the email flows, `verifyMfa` and
`signOut`) now call auth-js on a `createServerClient` from `@supabase/ssr`
instead of the Auth endpoints directly, so the session and PKCE cookies are
the ones `@supabase/ssr` writes. Flows the browser client starts can finish in
`exchangeCodeForSession`.

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `passwordGrant` from `better-supabase/server` | `signInWithPassword` on a `createServerClient`     |
| error code `code_verifier_missing`            | `pkce_code_verifier_not_found` (auth-js)           |
| verifier cookie `httpOnly`, 10 minutes        | the auth-js verifier cookie `@supabase/ssr` writes |
| `SignInWithOAuthParams.provider: string`      | `Provider` from `@supabase/supabase-js`            |

A link from a flow started before the upgrade fails the exchange once; ask
the user to request a new one.
