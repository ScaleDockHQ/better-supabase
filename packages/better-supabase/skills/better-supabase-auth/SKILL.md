---
name: better-supabase-auth
description: Read and check the caller in better-supabase apps, including sessions, typed claims, user profiles, OAuth clients and agents acting for a user, scopes, ended sessions and PermDock. Use when code reads auth, session or claims, when adding a custom access token hook, an OAuth or agent integration, sign-out, account deletion or role changes, or when the project has a permdock.config.ts.
---

# Auth with better-supabase

Every adapter resolves the caller once. It verifies the access token locally
against the project's JWKS, so a valid token costs no network call, and only
the Next.js proxy (`bs.proxy`) refreshes sessions. Don't call
`supabase.auth.getUser()` per request, and don't read cookies yourself.

## Workflow: read the caller

1. Take `auth` from the handler context (`ctx.auth`, `c.var.auth`,
   `context.auth`), or a token-free `AuthSession` from `await bs.session()`
   or `toSession(ctx.auth)`.
2. Branch on `kind` with an exhaustive `switch` that ends in a `never` check:

```ts
switch (auth.kind) {
  case "user": // auth.user.id, auth.claims
    break;
  case "service": // a secret key
    break;
  case "anon": // auth.reason: 'none' | 'expired' | 'signed_out' | 'refresh_failed'
    break;
  case "invalid": // auth.reason: 'token' | 'claims' | 'actor', answer 401
    break;
  default: {
    const unreachable: never = auth;
    return unreachable;
  }
}
```

3. Prefer the adapter's `allow` option (`['user']` by default) over checking
   `kind` by hand; it answers 401 or 403 as Problem Details.

Done when every `invalid` reason, `actor` included, ends in a 401 and no code
path treats `invalid` as `anon`.

## Workflow: type the claims

1. Describe the claims your access token hook adds with any Standard Schema
   and pass it to `betterSupabase.claims(schema)`. Use a loose object (`v.looseObject`,
   `z.looseObject`) so claims the schema doesn't list stay on the session.
   Make anything the hook doesn't always set optional or give it a default.
2. For display data users edit themselves (name, avatar), use
   `betterSupabase.userMetadata(schema)` and read `session.profile`.
3. Read roles, memberships, the tenant and entitlements from the verified
   claims only. Never from `user_metadata`, `session.profile`, a URL or a
   request body.

Done when `session.claims` is typed without casts, and a token whose claims
fail the schema gets a 401 with code `CLAIMS_INVALID`.

## Bearer callers: OAuth clients and agents

A token from the Supabase OAuth server carries `client_id` and `scope`; a
token exchanged for an agent carries an RFC 8693 `act` chain. The session
names who acts for the user:

| Token                                            | `session.actor`                                | `session.delegation` |
| ------------------------------------------------ | ---------------------------------------------- | -------------------- |
| The user's own                                   | not set                                        | not set              |
| `client_id: "c1"`, `scope: "openid crm.read"`    | `{ id: "c1", kind: "oauth-client" }`           | `{ scopes: [...] }`  |
| `act: { sub: "agent", act: { sub: "mcp-42" } }`  | `{ id: "agent", chain, ... }`                  | `{ scopes, chain }`  |
| `act: { kind: "support", sub, session_id, ... }` | `{ kind: "support", id, sessionId, readOnly }` | not set              |
| `act: { kind: "impersonation", sub, reason }`    | `{ kind: "impersonation", id, reason }`        | not set              |

- Limit what delegated tokens may do with the `scopes` guard option on
  `bs.route`, `bs.action`, `bs.handler` and `bs.middleware`. A missing
  scope answers 403 with an `insufficient_scope` challenge. Only an
  `oauth-client` actor is limited: the user's own token, a support session
  and an impersonated session are not.
- Switch on `session.actor.kind` with a `never` default: it is
  `oauth-client`, `support` or `impersonation`. An `act` with another `kind`
  resolves to `invalid` with reason `actor`.
- In MCP servers, refuse calls in `authorize` by reading
  `toSession(ctx.auth).delegation?.scopes` (the `better-supabase-api` skill).
- RLS still decides the rows: `sub` is the user, so a client sees at most
  what the user sees. Record `session.actor` (and `chain`) in audit data when
  a change was made by a client or an agent.

## Workflow: irreversible actions

Tokens stay valid until they expire (an hour by default), even after the user
signs out everywhere or an admin ends the session. Before an action you can't
undo (deleting the account, transferring ownership, rotating keys), check
that the session still exists:

```ts
import { err } from "better-supabase";
import { checkSession } from "better-supabase/server";

const ended = await checkSession(postgres.admin, auth);
if (ended) return err(ended); // unauthorized, code SESSION_REVOKED
```

It needs a connection that can read `auth.sessions` (`createPostgres().admin`).
Nothing calls it by default; keep it to the actions that need it.

Done when the irreversible action returns `SESSION_REVOKED` for a signed-out
session in a test.

## When claims change

A token carries the claims from when Auth issued it, so a revoked role or
membership lasts until the next refresh. When that window matters:

- Write policies that read the source of truth, for example
  `organization_id in (select better_supabase.member_org_ids())`, instead of
  the claim.
- For signed-out, banned or deleted users, add the `sessions` SQL module and a
  restrictive policy with `using ((select better_supabase.session_active()))`
  on the tables that guard sensitive data.
- After a change the user made themselves (joining an organization), call
  `supabase.auth.refreshSession()` in the browser.
- In Next.js, drop the user's cached views with
  `bs.invalidateSession(userId, { tags })`.

## Next.js caching

- Per-user data goes through `bs.cached()` inside your own
  `'use cache: private'` function. It tags the entry `bs:session:<user id>`
  and caps its lifetime at the token's.
- `bs.cached({ tags, life: { stale } })` adds tags and caps the stale time
  further, for example for a PermDock snapshot.
- Keep layouts synchronous: pass the `bs.session()` promise to
  `<SessionProvider>` and read it with `useSession()`.

## PermDock

When the project has a `permdock.config.ts`, PermDock owns the access token
hook, roles, memberships and the tenant claim. Read
[references/permdock.md](references/permdock.md) before touching the hook,
claims, tenant or entitlements.

## Don't

- Don't refresh sessions outside the proxy, and don't verify tokens by
  calling the Auth server.
- Don't use `bs.admin()` or the service role for a user's request.
- Don't downgrade an `invalid` caller to `anon`.
- Don't build 401 or 403 JSON by hand; return the `DbError` or use `allow`
  and `scopes`.
- Don't use `allow: ['anon']` for users from `signInAnonymously()`: `'anon'`
  means no session, and only `'anonymous'` admits anonymous sign-ins.

## Docs

https://bettersupabase.com/docs/auth.md,
https://bettersupabase.com/docs/frameworks/next.md (bearer callers),
https://bettersupabase.com/docs/auth/account-deletion.md,
https://bettersupabase.com/docs/frameworks/next-cache-components.md and
https://bettersupabase.com/docs/auth/permdock.md.
