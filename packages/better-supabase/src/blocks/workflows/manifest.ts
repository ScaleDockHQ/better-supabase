import type { BlockOf } from "../define-block.ts";
import type { WorkflowsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { workflowsEvents } from "./events.ts";
import { createWorkflows } from "./workflows.ts";

/** The `workflows` block's manifest (ADR 0029). */
export const workflowsBlock: BlockOf<
  "workflows",
  typeof createWorkflows,
  WorkflowsEvents,
  Record<never, never>,
  "workflows"
> = defineBlock({
  name: "workflows",
  schedules: [
    {
      name: "tick",
      cron: "* * * * *",
      runs: "schedules.tick() and admission.tick()",
      description:
        "Starts every due workflow schedule once and the queued starts that have room.",
    },
  ],
  sql: ["workflows"],
  events: workflowsEvents,
  provides: { workflows: (client) => client },
  create: createWorkflows,
  client: "workflows",
  category: "automation",
  description:
    "Engine-neutral workflow runs that members read through RLS, with a Realtime ping per status change and workflow_run.completed, .failed and .cancelled outbox events; cron schedules with idempotent fires, counting semaphores, admission control for starts (concurrency, debounce, singleton) and a retention purge.",
  recipes: ["workflow-canvas", "workflow-runs"],
});
