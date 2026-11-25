---
"better-supabase": minor
---

The authorization refresh joins its Realtime channel when the browser is idle (`requestIdleCallback`, else a timer), keeps one channel per client, topic and event, and skips the `caller_authz_version()` call on the first join when `SessionProvider` gets `liveVersion` (the bootstrap's `authzVersion`). A join after a reconnect still reads the version. Pass `liveVersion` to save the call on every page load.
