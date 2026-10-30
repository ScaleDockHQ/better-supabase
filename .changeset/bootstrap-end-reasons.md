---
"better-supabase": minor
---

`bsb.bootstrap()` tells a banned user from an ended session, the proxy hands refreshed cookies to the render, and `SessionProvider` can skip the authorization refresh.

- Bootstrap: the `bootstrap_<rpc>` wrappers return `end_reason` (`user_banned` or `session_not_found`) from the new `better_supabase.session_end_reason()`. The result carries it as `endReason`, the redirect uses `?reason=user_banned` for a banned user, and `reasons: { ended, banned }` sets other values, as in `verifySession`. Run `better-supabase upgrade` and generate a migration; a wrapper generated before reports `session_not_found` for both.
- Proxy: under `verifySession: "bootstrap"`, a session that `bsb.bootstrap()` found ended has its cookies cleared on its next request in the same process. The proxy also copies its `set-cookie` headers into `x-middleware-set-cookie`, so the render after a refresh reads the new token instead of the old one.
- React: `SessionProvider` takes `authzRefresh`, `false` or a test on the session, such as `(session) => !supportOf(session)` to keep a support session off the target user's topic.
