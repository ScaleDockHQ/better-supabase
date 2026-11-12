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
    entities: {
      onboarding: { mutability: "append-only", emits: { create: false } },
    },
    description:
      "Onboarding checklists per user or organization, run as enrollment programs: the completed steps, completed by hand or by an outbox event type. Organization checklists check onboarding.read and onboarding.complete.",
    recipes: ["onboarding-checklist"],
  });
