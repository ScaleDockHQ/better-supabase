# 0604: Account helpers take the server as their first argument

- Status: accepted
- Date: 2026-11-10
- Amends: 0450

## Context

`createServer` imported `deleteAccount`, `suspendAccount`, `endSessions` and `lastSignIns` so the
server could expose them as methods. Every adapter, every route and the proxy bundled that code
(the account helpers and their Auth error mapping) although few routes delete an account.

## Decision

The four methods leave the server object. `better-supabase/server/account` exports the same
functions with the server as the first argument: `deleteAccount(bsb, userId, options)`. The server
carries what they need under `ACCOUNT_PARTS` (the definition's event hub, the service client, the
admin Postgres client, the account transport and the audit sink), and `createNext` adds an `after`
hook that drops the user's caches and session memo, as its wrappers did. The transport-first
functions in `better-supabase/server/accounts` (ADR 0450) stay for apps without a server.
`codemod account-calls` rewrites the calls; it is not a typed rename, so its review line asks for a
look at each file.

## Consequences

Measured in the bundle baseline: `./server` 168,862 to 165,508 bytes, the shipped `next proxy`
consumer 66,631 to 64,832 and `hono` 72,250 to 70,468 (min plus gzip). That is 1.8 KB, well under
the 8 to 10 KB the plan hoped for, because the Auth error mapping and the audit hooks stay. A
breaking change for callers of the four methods, listed in the changeset and the upgrade guide.
