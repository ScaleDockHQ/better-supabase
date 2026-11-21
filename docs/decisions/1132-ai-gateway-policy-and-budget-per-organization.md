# 1132: Govern the AI Gateway per organization with settings and usage meters

- Status: accepted
- Date: 2026-11-21

## Context

The Vercel AI Gateway scopes budgets and controls to a team, a project, an API
key or a member. Its budgets have no tenant scope and don't count calls that use
a bring-your-own key (BYOK). A virtual model (`vmc/<slug>`) replaces the
request's `tags` with the tags its rule sets, so the `org:` tag that
`spendReconciliation` groups by is lost for those calls. `GatewayOptions` was an
untyped object, and the cost rows kept only four token counts and one cost.

The gateway's response carries `providerMetadata.gateway.cost`, `marketCost`,
`generationId` and `routing`, checked against the live docs and the installed
`@ai-sdk/gateway` types. `inferenceRegion`, `sessionId` and `sessionAffinity`
are accepted by the gateway but missing from its `GatewayProviderOptions`.

## Decision

Keep the tenant layer in the app and build it from existing blocks, with no new
SQL module:

- `GatewayOptions` is a structural copy of `GatewayProviderOptions`
  (`gateway-provider-options.ts`), plus the three untyped keys. `@ai-sdk/gateway`
  stays an optional peer.
- The policy is one `settings` row per organization under `ai.gateway_policy`
  (`gateway-policy.ts`). `applyGatewayPolicy` can only tighten a call's options.
- The budget is the quota of the `usage` block's `ai.cost` meter in micro-USD
  (`gateway-budget.ts`): `check` before a call, `settle` after it, once per
  generation through the `ai-cost:<generationId>` idempotency key. BYOK calls
  don't count unless `countByok` is set. The budget is soft.
- `gateway-cost.ts` reads cache read and write, reasoning tokens, market cost
  and the BYOK flag, backfills with a retrying, age-limited job handler, and
  checks the team's credits.
- `gateway-virtual-models.ts` adds virtual models to the catalog and attributes
  their spend by user instead of by tag.

## Alternatives considered

A new `ai-gateway` SQL module with its own policy and budget tables: about 45
files plus generated clients, a second quota engine next to `usage`, and no
database stack to test it here. The `settings` and `usage` blocks already hold
typed per-organization rows and period quotas.

Gateway budgets with one API key per organization: it scales with the number of
tenants, doesn't count BYOK and hides the tenant from the app's own checks.

A hard cap by reserving the estimate before the call: it needs a release step
for every failure path and the cost is not known until after the call.

## Consequences

A budget can be passed by the cost of the calls that run at the same time. The
policy and budget need the `settings` and `usage` blocks. Apps that spread a
user over several organizations must encode the organization in the gateway
`user` to attribute virtual model spend. `GatewayOptions` is typed, so a wrong
key or a non-string tag in app code now fails to compile. Revisit when the
gateway adds a tenant scope or when `GatewayProviderOptions` lists the regional
keys.
