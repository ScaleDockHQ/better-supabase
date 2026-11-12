import type { BlockOf } from "../define-block.ts";
import type { StateMachineEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { stateMachineEvents } from "./events.ts";
import { stateMachineSqlOptions } from "./options.ts";
import { createStateMachine } from "./state-machine.ts";

/** The `state-machine` block's manifest (ADR 0029). */
export const stateMachineBlock: BlockOf<
  "state-machine",
  typeof createStateMachine,
  StateMachineEvents
> = defineBlock({
  name: "state-machine",
  sql: ["state-machine"],
  options: { "state-machine": stateMachineSqlOptions },
  events: stateMachineEvents,
  create: createStateMachine,
  category: "work",
  entities: { status: { mutability: "editable", emits: { update: true } } },
  description:
    "Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.",
  recipes: ["work-item-board"],
});
