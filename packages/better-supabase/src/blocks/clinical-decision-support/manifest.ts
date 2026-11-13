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
  entities: {
    care_alert: { mutability: "state-machine" },
    care_rule: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Tenant rules for dose range, duplicate therapy and interactions over a record's medication orders, alerts that members acknowledge or override with a reason, and a decision context for external engines whose alerts are stored the same way.",
});
