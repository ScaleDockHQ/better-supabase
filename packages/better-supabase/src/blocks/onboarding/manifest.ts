import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `onboarding` block's manifest (ADR 0029). */
export const onboardingBlock: Block<"onboarding"> = defineBlock({
  name: "onboarding",
  sql: ["onboarding"],
  options: {
    onboarding: optionKeys(["checklists"]),
  },
  client: "onboarding",
  category: "operations",
  recipes: ["onboarding-checklist"],
});
