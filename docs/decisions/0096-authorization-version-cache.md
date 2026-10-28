# 0096: Give authorization libraries a version cache slot and a Realtime evictor

- Status: accepted
- Date: 2026-10-23

## Context

An authorization library that caches decisions per user needs to know when
a user's roles or grants changed. Re-reading them on every check costs a
database call per island, and a cache keyed only on the user id serves stale
decisions after a role change. better-supabase can't own that cache: it never
depends on an authorization library (invariant 15), and the decisions are
the library's. It also can't keep per-request state in module maps, which
leak between users on a shared instance.

## Decision

`createServer(def, { versions })` takes an `AuthzVersionCache`, typed
structurally in `src/core/authorizer.ts`: `evict(userId)` is all
better-supabase calls. The app creates it once at module scope.
`bindAuthorizer` passes `{ versions, memo }` as an `AuthorizerRuntime` to
every authorizer decision; `memo` is a `RequestMemo` the caller creates per
scope (`requestMemo()`), so nothing request-specific lives in module state.
Authorizers written before the runtime still get the call they always did
(`evaluateWith` passes the runtime only when there is one). The field is
optional, so the `AuthorizationProvider` contract stays at `apiVersion: 1`.

The token carries the version as `authz_ver`, set by an access token hook,
and `AuthSession` and `SessionSnapshot` read it as `authzVersion` (with
`issuedAt` from `iat`). `sessionCacheKey` includes it, so a cache keyed on
the session changes with the next token. `bsb.evictSession(userId)` evicts
the user from `versions`, from the session memo (ADR 0095) and from the
user's cache tags, including the tags an authorization provider names
through its optional `sessionTags(userId)` hook. `bsb.bootstrap()` returns
the version with the page's data and seeds `versions` with it (ADR 0115).

The sessions module's `authzVersions` option owns the version: a
`better_supabase.user_authz_versions` table, `bump_authz_versions(uuid[])`,
a `bump_authz_version()` trigger function to attach to the tables a user's
access comes from, and the `authz_ver` claim in the access token hook. A
trigger on the table broadcasts each change twice, with `realtime.send`:

- on `better_supabase:authz` (`AUTHZ_TOPIC`), which no `realtime.messages`
  policy opens, so only the service role reads it;
- on the user's own `authz:<uid>` topic, which a select policy opens to that
  user alone (`realtime.topic() = 'authz:' || auth.uid()`).

`subscribeAuthzVersions({ client, versions })` in
`src/server/authz-versions.ts` joins the first topic with the service-role
client and evicts each user a broadcast names. `topic`, `event` and
`userIdKey` default to the module's names and can point at a library's own
trigger; a per-user `authz:<uid>` topic evicts that user. It is idempotent
per `versions` instance (a `WeakMap`) and starts from the module that owns
the cache. In the browser, `<SessionProvider client>` joins `authz:<uid>`,
refreshes the token on a new version, runs `onAuthzChange` (usually
`bsb.refreshSessionCache` and `router.refresh()`) and tells the app's other
tabs through a `BroadcastChannel`. A pgTAP test covers the module.

## Alternatives considered

- A built-in version cache: it would decide the library's caching policy and
  its storage, and pull its shape into the core contract.
- Evicting from `instrumentation.ts`: the subscription would outlive or miss
  the cache instance the server uses. Starting it next to the cache ties
  their lifetimes together.
- One public channel for every user: users could listen to other users'
  authorization changes. Each user's topic is private and opens only to that
  user.
- Polling `session_active()` or the version from the browser: a database call
  per tab per interval, and a role change still waits for the next poll.

## Consequences

A role change takes effect on the next decision of every instance that
subscribed, without a per-check database read, and the user's open tabs
re-render with the new token in the background. A library ships its own
cache and passes it in; better-supabase only evicts. An app without a
version claim gets `authzVersion: null` and loses nothing. A new required
member of `AuthzVersionCache` would need a new `apiVersion`.
