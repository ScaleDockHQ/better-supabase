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
the session changes with the next token. `invalidateSession(userId)` evicts
the user from `versions`.

`subscribeAuthzVersions({ client, topic, event, userIdKey, versions })` in
`src/server/authz-versions.ts` joins a private Realtime channel with the
service-role client and evicts each user a broadcast names. The topic,
event and payload key are required, so no library's names are built in. It
is idempotent per `versions` instance (a `WeakMap`) and starts from the
module that owns the cache. It adds no `realtime.messages` policy: only the
service role listens. The fixture schema has a neutral `user_authz_versions`
table whose trigger calls `realtime.send`, with a pgTAP test.

## Alternatives considered

- A built-in version cache: it would decide the library's caching policy and
  its storage, and pull its shape into the core contract.
- Evicting from `instrumentation.ts`: the subscription would outlive or miss
  the cache instance the server uses. Starting it next to the cache ties
  their lifetimes together.
- A public channel with a `realtime.messages` policy: users could listen to
  other users' authorization changes.

## Consequences

A role change takes effect on the next decision of every instance that
subscribed, without a per-check database read. A library ships its own
cache and passes it in; better-supabase only evicts. An app without a
version claim gets `authzVersion: null` and loses nothing. A new required
member of `AuthzVersionCache` would need a new `apiVersion`.
