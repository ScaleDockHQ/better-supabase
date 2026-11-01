# 0189: Agents buy and call through checkout sessions, A2A and WebMCP

- Status: accepted
- Date: 2026-11-01

## Context

Shopping agents speak the Agentic Commerce Protocol (ACP) and the Universal
Commerce Protocol (UCP), prove a buyer's consent with Agent Payments Protocol
(AP2) mandates, pay API routes with x402 and talk to other agents over A2A.
Browsers are adding WebMCP so a page can offer tools to an agent. The repo
already has the parts underneath: orders and a payment provider port (ADR 0024),
Money (ADR 0037), signing keys (ADR 0033), ai-chat runs (ADR 0122) and `src/mcp`.

## Decision

A new `agent-checkout` block (ADR 0029) keeps two tables. `checkout_sessions` is
a thin record over an orders cart: protocol (`acp` or `ucp`), status, buyer
details, order and expiry, created with an idempotency key that is unique per
tenant and bound to a request hash. `agent_mandates` stores the credentials.
`orders`, `outbox` and `audit` are `integrates`, so the block installs without
them; the methods that need orders or signing answer an `invalid_request`
error with a hint. `complete_checkout_session` is service-only because the
orders checkout and `place_order` are.

A mandate is a compact JWS signed with the signing-keys owner's active key and
verified against its JWKS. It uses the AP2 v0.2 claim names for the type (`vct`),
subject, expiry and id. An open mandate caps one checkout (`max_total`) and is
checked every time. A closed mandate binds one session and the hash of the
cart and priced total and is used once. The use is recorded before the payment
runs, so a checkout that fails afterwards burns the mandate; this errs toward
asking the buyer again over charging twice. The block does not implement the AP2
delegation chain or SD-JWT selective disclosure, and the amount claims are its
own; a later `apiVersion` can add them.

`withPayment` and `paymentRequired` follow x402 v2 (`PAYMENT-REQUIRED`,
`PAYMENT-SIGNATURE`, `PAYMENT-RESPONSE`, CAIP-2 networks) over a structural
`X402Facilitator`. Settlement happens only when the handler answered below 400.

`agents` gains `agentCard` and `agentCardResponse` (A2A 1.0, one skill per public
agent) and `createA2AHandler`, a JSON-RPC endpoint with `SendMessage`,
`SendStreamingMessage`, `GetTask` and `CancelTask`. A task is an ai-chat run and
its context the chat. The app supplies the session per request, including the
`start` function that runs the model, so no AI SDK is imported. Streams poll
the run.

`better-supabase/webmcp` registers `BlockAction`s with `document.modelContext`
(falling back to the legacy `navigator.modelContext`) and turns the same
actions into MCP tools for `createMcp`. An action must declare a permission or
`null`; denied actions are not registered and each call checks again.

ACP, UCP, AP2, x402, A2A and WebMCP are pinned in `SPEC_PINS` and listed on the
standards page.

## Alternatives considered

- Full AP2 with SD-JWT and delegation: no stable library fits the runtime
  entries, and the partial form is documented as such.
- A new payment path in the block: duplicates the provider port (ADR 0024).
- An A2A SDK dependency: breaks the no runtime dependency rule.
- Serving MCP Apps `ui://` resources: `src/mcp` has no resource support, so this
  waits for it.

## Consequences

Agents can check out against any orders cart and the permission model decides
what they may do. The A2A endpoint is only as capable as the app's `start`
function. The JSON-RPC binding is the only A2A binding and push notifications
are not supported. Revisit the mandate claims when AP2 publishes a JWT profile.
