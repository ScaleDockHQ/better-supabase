import type { BlockOf } from "../define-block.ts";
import type { StateMachineEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { stateMachineEvents } from "./events.ts";
import { createStateMachine } from "./state-machine.ts";

/** The `state-machine` block's manifest (ADR 0029). */
export const stateMachineBlock: BlockOf<
  "state-machine",
  typeof createStateMachine,
  StateMachineEvents
> = defineBlock({
  name: "state-machine",
  sql: ["state-machine"],
  options: {
    "state-machine": optionKeys(["machines"]),
  },
  events: stateMachineEvents,
  create: createStateMachine,
  category: "work",
});
