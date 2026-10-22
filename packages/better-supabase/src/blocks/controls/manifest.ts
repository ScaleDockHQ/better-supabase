import type { BlockOf } from "../define-block.ts";
import type { ControlsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createControls } from "./controls.ts";
import { controlsEvents } from "./events.ts";
import { controlsSqlOptions } from "./options.ts";
import {
  controlFrameworkInputSchema,
  controlInputSchema,
  evidenceTaskInputSchema,
  policyInputSchema,
} from "./schemas.ts";

/** The `controls` block's manifest (ADR 0029). */
export const controlsBlock: BlockOf<
  "controls",
  typeof createControls,
  ControlsEvents
> = defineBlock({
  name: "controls",
  sql: ["controls"],
  options: { controls: controlsSqlOptions },
  events: controlsEvents,
  schemas: {
    control_framework: { input: controlFrameworkInputSchema },
    control: { input: controlInputSchema },
    evidence_task: { input: evidenceTaskInputSchema },
    policy: { input: policyInputSchema },
  },
  create: createControls,
  recipes: ["control-posture"],
  category: "admin",
});
