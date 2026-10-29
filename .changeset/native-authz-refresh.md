---
"better-supabase": minor
---

Native apps follow role changes, PowerSync reconnects on them, and bootstrap reports the live authorization version. The [0.43 to 0.44 guide](https://bettersupabase.com/docs/migration/0.43-to-0.44) lists what to check.

Bootstrap version fields, old to new:

| 0.43                                      | 0.44                                     |
| ----------------------------------------- | ---------------------------------------- |
| `boot.authzVersion` (the token's version) | `boot.tokenAuthzVersion`                 |
| no field                                  | `boot.authzVersion` (the live version)   |
| no field                                  | `boot.stale` (the live version is ahead) |

- Bootstrap: the `bootstrap_<rpc>` wrappers read `better_supabase.caller_authz_version()` and return the live version next to the token's. `getAccess(boot)` seeds the version cache with the live version, so a role taken away since sign-in is gone on the next render. Run `better-supabase upgrade` and generate a migration.
- Servers: `bootstrapFor` and `accessFor` on every server, and a `bootstrapSchema` option. `createNext` builds on them.
- Expo: `bsb.bootstrap(request, { rpc })`, `bsb.getAccess(request, { bootstrap })`, and `bsb.cached(request, { tables })` with the tags an app cache stores the result under (`sessionTag` and the tag helpers are exported from `better-supabase/server`).
- Native: `SessionProvider` from `better-supabase/react/native` takes React Native's `AppState`, resubscribes when the app becomes active, catches up on a missed change, and reconnects PowerSync after the refresh. `startNativeAuthzRefresh` from `better-supabase/client/native` does the same without React.
- PowerSync: `syncWithAuth` reconnects when a new token for the same user carries another tenant or `authz_ver`, and returns an `AuthSync` with `reconnect()`, queued behind sign-in and sign-out. `tenantClaim` and `fingerprint` adjust what counts as a change.
- CLI: `better-supabase powersync streams` writes streams for blocks over the app's own tables, reading their columns from the saved snapshot.
- Authorization providers: `versions: { function }` names the provider's version function; the sessions module then creates no version table.
- Auth: for a local project URL the default issuer check accepts the loopback and emulator hosts, and `auth.loopbackAliases` adds more, such as a phone's LAN address.
- Approvals: a tenant step that names only users rejects a numeric `required` above the number of users, as the config does, and saves `"all"` as that number.
- Timeline: messages in a record's comment thread have the type `comment.posted`, and a stored entry that a read-time source also returns appears once.
