---
"better-supabase": minor
---

AI Gateway governance per organization in `better-supabase/ai-sdk`.

- `GatewayOptions` is now typed after the SDK's `GatewayProviderOptions` (a structural copy, so
  `@ai-sdk/gateway` stays an optional peer). Upgrade note: a misspelled key or a non-string entry in
  `tags`, `only` or `order` is now a compile error. Fix the call site; nothing changes at runtime.
- `parseGatewayPolicy`, `gatewayPolicySetting`, `gatewayPolicyReader`, `mergeGatewayPolicies`,
  `applyGatewayPolicy` and `governedGatewayOptions` give each organization a policy (zero data
  retention, allowed providers, region, prompt caching, headquarters) stored in the settings block.
- `createGatewayBudget` checks an organization's budget before a call and settles the cost after it,
  on the usage block's `ai.cost` meter.
- `gatewayCostOf`, `gatewayCostEntries`, `gatewayRunRelease` and `costUsage` keep cache read and write
  tokens, reasoning tokens and the market cost. `gatewayCostBackfill` retries until the gateway knows
  the generation, and `checkGatewayCredits` and `creditsMonitor` watch the team's credits.
- `virtualModelCatalogRefresh` adds virtual models to the model catalog, and
  `virtualModelSpendReconciliation` attributes their spend by user, because a virtual model replaces the
  request tags.
