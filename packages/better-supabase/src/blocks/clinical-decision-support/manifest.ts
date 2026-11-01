import type { BlockOf } from "../define-block.ts";
import type { ClinicalDecisionSupportEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createClinicalDecisionSupport } from "./clinical-decision-support.ts";
import { clinicalDecisionSupportEvents } from "./events.ts";
import { careRuleInputSchema } from "./schemas.ts";

/** The `clinical-decision-support` block's manifest (ADR 0029). */
export const clinicalDecisionSupportBlock: BlockOf<
  "clinical-decision-support",
  typeof createClinicalDecisionSupport,
  ClinicalDecisionSupportEvents
> = defineBlock({
  name: "clinical-decision-support",
  sql: ["clinical-decision-support"],
  events: clinicalDecisionSupportEvents,
  schemas: { care_rule: { input: careRuleInputSchema } },
  create: createClinicalDecisionSupport,
  recipes: [],
  category: "people",
});
