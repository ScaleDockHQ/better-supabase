import type { BlockOf } from "../define-block.ts";
import type { WorkflowBuilderEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { workflowBuilderEvents } from "./events.ts";
import { workflowBuilderSqlOptions } from "./options.ts";
import { createWorkflowBuilder } from "./workflow-builder.ts";

/** The `workflow-builder` block's manifest (ADR 0029). */
export const workflowBuilderBlock: BlockOf<
  "workflow-builder",
  typeof createWorkflowBuilder,
  WorkflowBuilderEvents,
  { readonly workflows: "optional" }
> = defineBlock({
  name: "workflow-builder",
  sql: ["workflow-builder"],
  options: {
    "workflow-builder": workflowBuilderSqlOptions,
  },
  events: workflowBuilderEvents,
  consumes: { workflows: "optional" },
  create: createWorkflowBuilder,
  client: "workflow-builder",
  category: "operations",
});
