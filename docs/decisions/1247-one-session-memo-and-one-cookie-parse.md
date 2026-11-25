# 1247: Share one session memo and parse a session cookie once

- Status: accepted
- Date: 2026-11-24

## Context

`processSessionMemo` returned a private memo whenever the caller passed
`counters`, and every server of the Next.js example passes them. A session the
proxy verified and seeded after a refresh never reached a render, so each
refresh cost 2 verifications. A private cache scope also builds its own
`Request`, so the per-list `WeakMap` in `ssrSession` missed and a page such as
`/customers` decoded the same cookie dozens of times.

A measurement of the verification itself (3,000 runs, ES256, one key) gave 72
microseconds through `verifyCredentials` and 50 microseconds with a persistent
`jose` key set. `@supabase/server` builds a new key set per call and accepts a
URL or an inline set, never a resolver.

## Decision

`processSessionMemo` returns the shared memo for any call that sets no clock,
bound or ttl, and attaches `counters` to it (`SessionMemo.count`). Every counter
object sees every lookup, so the harness still counts verifications per
process.

`ssrSession` keeps its per-list memo and adds a 32-entry map keyed by the raw
chunks of the session cookie. A changed cookie has a different key, so it never
returns a stale session.

The key import per `kid` stays with `@supabase/server`. The 22 microseconds it
costs apply only to a memo miss, which the shared memo makes rare, so a wrapper
around the verifier is not worth carrying until upstream takes a resolver.

## Alternatives considered

- Hold a `jose` key set in better-supabase and verify without
  `@supabase/server`. It saves 22 microseconds per miss and duplicates the
  claims and audience checks.
- Leave the private memo for counters and seed both memos. It doubles the
  state and still misses after a sign-in.

## Consequences

A refresh in the proxy costs 1 verification instead of 2, and a render reads
the parsed session from memory. Tests that want a private memo pass a clock,
`max` or `ttlMs`. Revisit the key import when `@supabase/server` accepts a
resolver.
