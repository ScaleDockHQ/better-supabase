import type { BlockOf } from "../define-block.ts";
import type { ComplianceEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCompliance } from "./compliance.ts";
import { complianceEvents } from "./events.ts";
import {
  controlFrameworkInputSchema,
  controlInputSchema,
  evidenceTaskInputSchema,
  policyInputSchema,
} from "./schemas.ts";

/** The `compliance` block's manifest (ADR 0029). */
export const complianceBlock: BlockOf<
  "compliance",
  typeof createCompliance,
  ComplianceEvents
> = defineBlock({
  name: "compliance",
  sql: ["compliance"],
  events: complianceEvents,
  schemas: {
    control_framework: { input: controlFrameworkInputSchema },
    control: { input: controlInputSchema },
    evidence_task: { input: evidenceTaskInputSchema },
    compliance_policy: { input: policyInputSchema },
  },
  create: createCompliance,
  recipes: ["control-posture"],
  category: "admin",
  entities: {
    control: { mutability: "editable", emits: { create: true, update: true } },
    control_framework: { mutability: "editable", emits: { update: false } },
    evidence_task: { mutability: "editable", emits: { update: false } },
    compliance_policy: { mutability: "editable", emits: { update: false } },
  },
  description:
    "Compliance frameworks and their controls, evidence linked to controls (attachments or notes, with a validity date), recurring evidence tasks with assignees and an overdue state, a status rollup per framework, and policies published as frozen versions that members acknowledge through the acknowledgements block.",
});
