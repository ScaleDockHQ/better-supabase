import type { BlockOf } from "../define-block.ts";
import type { AutomationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAutomations } from "./automations.ts";
import { automationsEvents } from "./events.ts";
import { automationsSqlOptions } from "./options.ts";

/** The `automations` block's manifest (ADR 0029). */
export const automationsBlock: BlockOf<
  "automations",
  typeof createAutomations,
  AutomationsEvents
> = defineBlock({
  name: "automations",
  sql: ["automations"],
  options: { automations: automationsSqlOptions },
  events: automationsEvents,
  create: createAutomations,
  category: "automation",
  entities: {
    automation: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "Tenant-editable automations: a filter tree over a subject type's field catalog, tested when a trigger event happens, with action references the action registry runs. Blocks ship default automations (rule_defaults) that every organization gets a copy of, may turn off or edit, and can reset. rule_matches() evaluates a tree in SQL the same way evaluateFilterQuery does in TypeScript.",
  recipes: ["rule-builder"],
  actions: [
    { kind: "approvals.request", title: "Request an approval" },
    { kind: "notify", title: "Send a notification" },
    { kind: "set_field", title: "Set a field" },
    { kind: "webhook", title: "Send a webhook" },
    { kind: "workflow", title: "Start a workflow" },
  ],
});
