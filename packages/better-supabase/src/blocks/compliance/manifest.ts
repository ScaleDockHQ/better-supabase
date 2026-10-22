import type { BlockOf } from "../define-block.ts";
import type { ComplianceEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCompliance } from "./compliance.ts";
import { complianceEvents } from "./events.ts";
import { complianceSqlOptions } from "./options.ts";
import {
  controlFrameworkInputSchema,
  controlInputSchema,
  evidenceTaskInputSchema,
  policyInputSchema,
} from "./schemas.ts";

/** The `controls` block's manifest (ADR 0029). */
export const complianceBlock: BlockOf<
  "compliance",
  typeof createCompliance,
  ComplianceEvents
> = defineBlock({
  name: "compliance",
  sql: ["compliance"],
  options: { compliance: complianceSqlOptions },
  events: complianceEvents,
  schemas: {
    control_framework: { input: controlFrameworkInputSchema },
    control: { input: controlInputSchema },
    evidence_task: { input: evidenceTaskInputSchema },
    policy: { input: policyInputSchema },
  },
  create: createCompliance,
  recipes: ["control-posture"],
  category: "admin",
});
