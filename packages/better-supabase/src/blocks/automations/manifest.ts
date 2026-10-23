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
  recipes: ["rule-builder"],
  actions: [
    { kind: "approvals.request", title: "Request an approval" },
    { kind: "notify", title: "Send a notification" },
    { kind: "set_field", title: "Set a field" },
    { kind: "webhook", title: "Send a webhook" },
    { kind: "workflow", title: "Start a workflow" },
  ],
});
