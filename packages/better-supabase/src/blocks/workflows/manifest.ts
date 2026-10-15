import type { BlockOf } from "../define-block.ts";
import type { WorkflowsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { workflowsEvents } from "./events.ts";
import { createWorkflows } from "./workflows.ts";

/** The `workflows` block's manifest (ADR 0029). */
export const workflowsBlock: BlockOf<
  "workflows",
  typeof createWorkflows,
  WorkflowsEvents
> = defineBlock({
  name: "workflows",
  sql: ["workflows"],
  events: workflowsEvents,
  provides: {
    workflows: (client) => client,
  },
  create: createWorkflows,
  client: "workflows",
  category: "operations",
});
