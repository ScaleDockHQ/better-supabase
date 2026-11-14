# 0909: Declare plan limits and meters in block manifests

- Status: accepted
- Date: 2026-11-14

## Context

`usage` has quotas per tenant or plan, and `billing` and `entitlements` resolve
plans, but a block method never checked a plan limit before it created, and a
mutating method never recorded a meter. Apps wrote a `before` hook per method
(EX-1312, EX-1314). Quota naming (EX-1313) was assumed to vary across about 18
blocks. A scan of every block option schema finds one limiting option
(`drive.quota`); the other limits are per-row columns (`rateLimit` on API keys
and incoming webhooks) and the `rate-limit` block. The error codes are already
two: `quota_exceeded` and `rate_limited`, both 429 with `retryAfter`.

## Decision

A manifest takes `limits` and `meters`, keyed by client method name, in
`src/blocks/metering.ts`. `usage` provides a `meter` port, and
`createBlocks({ metering: true })` wraps the declaring blocks' methods with
hooks built from the declarations, ahead of the app's own hooks. A limit calls
`canConsume` in `before` and returns `quota_exceeded` with `meter` and `limit`.
A meter calls `record` in `after`, only for a successful result. Metering is
off by default and does nothing without the `usage` block.

A plan limit is a deliberate gate and may change a result, which invariant 5
forbids for event handlers and sinks. A meter is not a gate: its failure is
logged and never changes the result. The first declarations are
`organizations.invite` (limit on `seats`) and `api-keys.create` (limit and meter
on `api_keys_created`).

Quota naming: a limiting block option is named `quota` and takes `BlockQuota`
(`{ meter, quantity? }`); a test fails when another option name matches
quota, rate limit or throttle. The two error codes stay: `quota_exceeded` for
quotas and plan limits, `rate_limited` for request rates.

## Alternatives considered

Gating through `consume` makes check and record atomic, but it counts a call
that then fails. Renaming `rateLimit` columns to `quota` would merge two
concepts with different semantics. Merging the two error codes would break
adapters that map them (`problemResponse`, workflow steps, the chat adapter).

## Consequences

Apps get seat and row limits by declaration. The check is not atomic with the
call, so a burst can pass; `consume` stays the strict path. More blocks can
add declarations without a new ADR.
