import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { onboardingSqlOptions } from "./options.ts";

/** The `onboarding` block's manifest (ADR 0029). */
export const onboardingBlock: Block<"onboarding"> = defineBlock({
  name: "onboarding",
  sql: ["onboarding"],
  options: {
    onboarding: onboardingSqlOptions,
  },
  client: "onboarding",
  category: "operations",
  recipes: ["onboarding-checklist"],
});
