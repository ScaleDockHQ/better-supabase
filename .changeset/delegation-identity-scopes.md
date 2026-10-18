---
"better-supabase": minor
---

`session.delegation.scopes` and `delegationOf(claims).scopes` leave out the OpenID Connect identity scopes, exported as `IDENTITY_SCOPES` from `better-supabase/server` (`openid`, `email`, `profile`, `phone`, `address`, `offline_access`). They grant no permission. A token whose `scope` names only identity scopes still has a delegation, with `scopes: []`, so an agent on it stays limited to its scopes. Code that looked for `openid` in `delegation.scopes` should read `claims.scope` instead.
