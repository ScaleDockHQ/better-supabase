# 1134: Run agents on Supabase with the sandbox firewall, Connect events and Chat history

- Status: accepted
- Date: 2026-11-21

## Context

The plan asked for a sandbox network policy that allows only the project host and injects a
short-lived token at the firewall, an eve sandbox provider with per-tenant snapshots, a route for
Connect and MCP event deliveries with per-tenant subscriptions, eve connection parity, and a Chat
SDK history config on our identity resolver.

`@vercel/sandbox` 4.1.0 already brokered credentials: `brokered` and `gatewayOnly` (ADR 0112) use a
rule's `transform` to add headers at the firewall. What was missing was a policy for the project
itself, and a way to refuse other paths: a request that matches no rule passes unchanged, so only a
final `response` rule with no `match` denies it. eve 1.3.0 already ships `eve/sandbox/vercel`
with `networkPolicy`, `setNetworkPolicy` and template snapshots, and its rule type has no
`response` rule. `@vercel/connect` 2.9.5 has `experimental_verifyMcpEvent`, which verifies a
delivery but does not deduplicate it. Chat SDK 4.45 has `history.user` with an `identity`
resolver and `history.user.delete`.

## Decision

`supabaseAccess` and `supabaseAccessFrom` in `better-supabase/vercel-sandbox` build a policy for
the project host: one `transform` rule per allowed service path adds `authorization`, `apikey`
and a pinned `host`, and a final 403 `response` rule answers other paths. `denyOtherPaths: false`
omits it for eve's rule type. The policy refuses a `service_role` JWT, a `sb_secret_` key and a
non-https URL, and ends the session a minute before the token expires.

`connectEventRoute` in `better-supabase/vercel-connect` takes the verifier as an argument, so it
adds no lazy import. It writes to the outbox with the key `connect:<deliveryId>`, which makes a
redelivery a no-op, and takes the tenant and subject from the subscription row.

Subscriptions live in a documented table, `connect_event_subscriptions`, read through a
`SqlClient`, and not in a SQL module. A module would need the catalog, `db:gen`, a pgTAP file and
the block registry for one lookup table that has no user-facing API, and the table is private to
the server.

`connectAuth` in `better-supabase/eve` wraps `connect` from `@vercel/connect/eve` and sets
`createSubject` to the subject `vercelConnectCredentials` uses, so grants are shared.

`chatHistory` and `eraseChatHistory` in `better-supabase/chat-sdk` build `history.user` from
`principalByIdentity`, keyed `user:<id>`, and delete that key.

We do not add an eve sandbox provider or per-tenant snapshot ids. eve's Vercel sandbox covers
both, and `ai_sandboxes` has no snapshot column. We do not add eve connection evict, resume or
device code handling: they belong to the Vercel Connect cache change of another pull request.

## Alternatives considered

A SQL module for subscriptions: rejected for the cost above. A lazy import of
`@vercel/connect/mcp` in the route: rejected, since passing the function in keeps
`lazy-imports.mdc` unchanged. Keying chat history by email or platform id: rejected, because it
splits one person's history and can't be erased by user.

## Consequences

An app creates the subscriptions table itself, from the SQL on the Connect events page. With eve,
`denyOtherPaths: false` lets other project paths be reached without the token. Thread caches that
adapters write are not erased with a user and expire with `history.thread.ttlMs`.
