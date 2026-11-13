import type { BlockOf } from "../define-block.ts";
import type { HiringEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { HIRING_AUTOMATIONS } from "./automations.ts";
import { hiringEvents } from "./events.ts";
import { createHiring } from "./hiring.ts";
import { hiringSqlOptions } from "./options.ts";

/** The `hiring` block's manifest (ADR 0029). */
export const hiringBlock: BlockOf<"hiring", typeof createHiring, HiringEvents> =
  defineBlock({
    name: "hiring",
    sql: ["hiring"],
    options: { hiring: hiringSqlOptions },
    events: hiringEvents,
    create: createHiring,
    category: "people",
    entities: {
      job_opening: { mutability: "state-machine" },
      application: { mutability: "state-machine", emits: { create: true } },
      interview: { mutability: "state-machine" },
    },
    concerns: ["lifecycle"],
    description:
      "Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.",
    recipes: ["hiring-board"],
    automations: HIRING_AUTOMATIONS,
  });
