import type { BlockOf } from "../define-block.ts";
import type { FeatureFlagsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createFeatureFlags } from "./admin.ts";
import { featureFlagsEvents } from "./events.ts";
import { featureFlagsSqlOptions } from "./options.ts";

/** The `flags` block's manifest (ADR 0029). */
export const featureFlagsBlock: BlockOf<
  "feature-flags",
  typeof createFeatureFlags,
  FeatureFlagsEvents
> = defineBlock({
  name: "feature-flags",
  sql: ["feature-flags"],
  options: { "feature-flags": featureFlagsSqlOptions },
  events: featureFlagsEvents,
  create: createFeatureFlags,
  category: "growth",
  recipes: ["feature-flag-toggles"],
});
