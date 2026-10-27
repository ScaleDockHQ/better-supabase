---
"better-supabase": minor
---

Breaking: the public auth names follow supabase-js and Next.js, and tenant is the public word again. Run `npx better-supabase@latest codemod 0.31`, then read the [0.30 to 0.31 guide](https://bettersupabase.com/docs/migration/0.30-to-0.31).

| 0.30                                                  | 0.31                                                                    |
| ----------------------------------------------------- | ----------------------------------------------------------------------- |
| `auth.organization`, `requireOrganization`            | `auth.tenant`, `requireTenant`                                          |
| `OrganizationConfig`                                  | `TenantConfig`                                                          |
| `bsb.session()`, `bsb.getRequestSession()`            | `bsb.claims()`, `bsb.getClaims()`                                       |
| `bsb.contextForSession()`                             | `bsb.contextFromSession()` (a snapshot, or a session with `{ token }`)  |
| `AuthState.profile`, `AuthSession.profile`            | `userMetadata`                                                          |
| caller kinds and `allow` values `anon`, `service`     | `none`, `secret`                                                        |
| `bsb.signIn()`                                        | removed: `bsb.signInWithPassword()`                                     |
| `bsb.authorizeUrl()`, `OAuthStart`                    | `bsb.signInWithOAuth()`, `SignInWithOAuthParams`                        |
| `bsb.exchangeCode()`, `CodeExchange`                  | `bsb.exchangeCodeForSession()`, `ExchangeCodeParams`                    |
| `endedSession`, `checkSession`, `EndedSessionOptions` | `verifySession`, `VerifySessionOptions`                                 |
| `sessionEnded`, `sessionEndedReason`                  | `sessionVerified: false`, `reason` (`session_not_found`, `user_banned`) |
| `refreshSkewSeconds`                                  | `leeway`                                                                |
| `expiredPrefetch: "protect"`                          | `onExpiredPrefetch: "redirect"`                                         |
| `bsb.invalidateSession()`, `bsb.forgetSession()`      | `bsb.evictSession()`, which returns a promise                           |
| `bsb.cacheTag()`, `bsb.cacheTags()`                   | `bsb.tag()`, `bsb.tags()`                                               |

The actor kinds (`ctx.actor.kind`), event subscribers and the Postgres roles keep `anon` and `service`.
