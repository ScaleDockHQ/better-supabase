---
"better-supabase": minor
---

Open pages pick up a role or grant change without waiting for the token to rotate. Run `better-supabase codemod 0.35` to rename the `SessionProvider` prop and list the lines to review.

- `blocks.sessions.options.authzVersions` adds `better_supabase.user_authz_versions`, the `bump_authz_version()` trigger function (it reads the user column from its argument, default `user_id`), `bump_authz_versions(uuid[])`, `authz_version(uid)` for the access token hook, and a broadcast on `AUTHZ_TOPIC` for servers and on the private `authz:<uid>` topic, which only that user may read.
- `SessionProvider` holds the session in a store. With `client` (a browser Supabase client) it listens on `authz:<uid>`: the visible tab refreshes the token and calls `onAuthzChange`, then tells the other tabs over the `better-supabase:session` `BroadcastChannel`, and they call `onAuthzChange` without a second refresh.
- `bsb.refreshSessionCache()` is a Server Action that drops the caller's own `bsb.cached()` entries; re-export it from a `"use server"` file and call it from `onAuthzChange`.
- `AuthorizationHooks.sessionTags(userId)` adds a provider's own cache tags to `bsb.cached()` entries, and `evictSession`, sign-out and `refreshSessionCache` clear them. The hook is optional, so `apiVersion: 1` stays.
- `subscribeAuthzVersions` defaults `topic`, `event` and `userIdKey` to what `authzVersions` sends, and a per-user `authz:<uid>` topic evicts that user. `AUTHZ_TOPIC`, `AUTHZ_EVENT` and `authzUserTopic` are exported from `better-supabase/server`.

Breaking changes:

- `SessionProvider` takes `session` instead of `sessionPromise`. It accepts a resolved `AuthSession` or a promise.
- `sessionStatusRoute` defaults to `verifySession: false`: it reads the verified claims only. Pass `verifySession: true` to ask Auth on every check.
