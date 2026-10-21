import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createOnboarding } from "./onboarding.ts";
import { onboardingSqlOptions } from "./options.ts";

/** The `onboarding` block's manifest (ADR 0029). */
export const onboardingBlock: BlockOf<"onboarding", typeof createOnboarding> =
  defineBlock({
    name: "onboarding",
    sql: ["onboarding"],
    options: { onboarding: onboardingSqlOptions },
    create: createOnboarding,
    client: "onboarding",
    category: "growth",
    recipes: ["onboarding-checklist"],
  });
