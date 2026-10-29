# 0129: Native apps refresh on the authorization version and reconnect PowerSync; bootstrap reports the live version

- Status: accepted
- Date: 2026-10-29

## Context

ADR 0096 lets an open browser tab follow a role change: the database bumps
the user's authorization version, broadcasts it on `authz:<uid>`, and the
browser `SessionProvider` refreshes the token. ADR 0115 reads a page's user
data in one `bootstrap_<rpc>` call.

An Expo app on iOS and Android, with PowerSync on the device and server
rendered web routes, had three gaps.

- The browser provider follows tab visibility and a `BroadcastChannel`. React
  Native has neither, and the OS closes the Realtime socket in the background,
  so a change made while the app was away never arrived.
- PowerSync evaluates sync streams when a client connects, with the claims of
  the token it was given. A refreshed token changed nothing until the client
  reconnected, so the device kept rows the user had lost, until the next cold
  start.
- The bootstrap wrappers returned the token's `authz_ver`. Seeding the server's
  version cache from that hid a role change the token predates, and a loader
  could not tell that the token was behind. Bootstrap also lived only in
  `createNext`, so Expo loaders had nothing to call.

Authorization libraries that keep their own versions had to accept a second
version table from the sessions module.

## Decision

`better-supabase/react/native` exports a `SessionProvider` that takes React
Native's `AppState`. It subscribes to the user's topic only while the app is
active, reads the live version on every join, and refreshes when the live
version is ahead of the token's, so it catches up on return. With
`powersync`, it calls `reconnect()` after the refresh.
`startNativeAuthzRefresh` in `better-supabase/client/native` is the same
logic without React. Both share one refresh core with the browser provider
(`client/authz-refresh.ts`).

`syncWithAuth` fingerprints the user, the active tenant and `authz_ver`, and
reconnects when a new token for the same user changes the fingerprint. It
returns an `AuthSync`: the cleanup function, plus `reconnect()`, queued with
the connect and disconnect steps so a sign-out always wins. `tenantClaim` and
`fingerprint` adjust the fingerprint.

The bootstrap wrappers return the live version from
`better_supabase.caller_authz_version()`, a definer function that reads only
the caller's version, next to the token's (`token_authz_version`).
`Bootstrap` gains `tokenAuthzVersion` and `stale`, and `authzVersion` now
means the live version. `bootstrapFor` and `accessFor` move to every server
(`server/bootstrap.ts`), with a `bootstrapSchema` option. `createNext` builds
on them, and `createExpo` gains `bsb.bootstrap`, `getAccess` and
`bsb.cached`, the last returning the tags an app-side cache stores a result
under.

`AuthorizationProvider.versions: { function }` names a provider's version
function; the sessions module then reads it and creates no table. The
contract stays `apiVersion: 1`, because the key is optional.

The default issuer check accepts the loopback and emulator hosts for a local
project URL, and `auth.loopbackAliases` adds more, so tokens issued to an
emulator or a phone verify against the local stack without `issuer: false`.

## Alternatives considered

- **Refresh the token on a short timer on native.** It costs an Auth call per
  device per interval and still leaves a gap of one interval.
- **Reconnect PowerSync from the app.** Every app would race the reconnect
  against sign-out and sign-in itself. Queuing it inside `syncWithAuth` keeps
  the order in one place.
- **A new `liveAuthzVersion` field, leaving `authzVersion` as the token's.**
  Every reader of `authzVersion` wanted the live value for its permission
  checks and cache keys; keeping the old meaning would leave the hidden role
  change in place for everyone who doesn't migrate.
- **Bootstrap in `better-supabase/expo` only.** Hono, SvelteKit and the other
  adapters would need a copy each; one implementation on `createServer`
  serves them all.

## Consequences

A revoked role reaches a device in the foreground within one broadcast, and
on return from the background at the next app activation, and the sync
service drops the rows at the reconnect. Loaders see `stale` and check
permissions against the live version.

Code that read `Bootstrap.authzVersion` as the token's version must read
`tokenAuthzVersion`. The wrappers change, so the sessions module SQL must be
regenerated. Each reconnect costs one PowerSync connection setup per role
change or tenant switch.

The manual check against a real sync service stays a release step (the
`expo-powersync` example's README), because the tests run a fake one.
Revisit when PowerSync offers a way to re-evaluate streams on a token refresh
without reconnecting.
