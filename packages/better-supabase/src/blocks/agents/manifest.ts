import type { BlockOf } from "../define-block.ts";
import type { AgentsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createAgents } from "./agents.ts";
import { agentsEvents } from "./events.ts";

/** The `agents` block's manifest (ADR 0029). */
export const agentsBlock: BlockOf<"agents", typeof createAgents, AgentsEvents> =
  defineBlock({
    name: "agents",
    sql: ["agents"],
    options: {
      agents: optionKeys(["maxInstructions"]),
    },
    events: agentsEvents,
    create: createAgents,
    category: "ai",
  });
