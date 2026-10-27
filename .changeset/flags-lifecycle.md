---
"better-supabase": minor
---

Feature flags keep a history and roll out on a schedule (breaking). Every `save_flag` records a revision with an optional message, and `createFlags()` gains `history(key)` and `restore(key, revision)`. `rolloutVariant` becomes `rolloutVariants`, a weighted split drawn from a second bucket so growing a rollout never moves a target between variants; `better-supabase upgrade` moves a stored variant over with weight 100. `rolloutSchedule` raises the percentage in steps, and rules can name shared segments (`saveSegment`, `segments`, `removeSegment`). The provider takes `onEvaluate`.

`better-supabase/flags-sdk` adds `flagsDiscoveryHandler` for discovery routes outside Next.js, `explorerOverrides` and `withExplorerOverrides` for toolbar overrides on the OpenFeature path, `toFlagsSdkDefinition`, `flagDrift` and `vercelEnvironmentContext`. `better-supabase/testing` adds `flagOverrideCookie`.

| 0.31                         | 0.32                                                |
| ---------------------------- | --------------------------------------------------- |
| `rolloutVariant: "on"`       | `rolloutVariants: [{ variant: "on", weight: 100 }]` |
| `rollout_variant` column     | `rollout_variants`                                  |
| `save_flag(key, definition)` | `save_flag(key, definition, message)`               |
