import type { BlockOf } from "../define-block.ts";
import type { LimsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { limsEvents } from "./events.ts";
import { createLims } from "./lims.ts";
import { limsSqlOptions } from "./options.ts";
import { limsMethodInputSchema, limsSampleInputSchema } from "./schemas.ts";

/** The `lims` block's manifest (ADR 0029). */
export const limsBlock: BlockOf<"lims", typeof createLims, LimsEvents> =
  defineBlock({
    name: "lims",
    sql: ["lims"],
    options: { lims: limsSqlOptions },
    events: limsEvents,
    schemas: {
      lims_sample: { input: limsSampleInputSchema },
      lims_method: { input: limsMethodInputSchema },
    },
    create: createLims,
    recipes: [],
    category: "work",
    entities: {
      lims_sample: { mutability: "state-machine" },
      lims_method: {
        mutability: "editable",
        emits: { create: true, update: true },
      },
      lims_result: { mutability: "state-machine", emits: { create: true } },
    },
    concerns: ["lifecycle", "search"],
    description:
      "Samples, test methods with specification limits, results through forms, a nonconformity case for every out of specification result and instruments from assets that must hold a valid qualification.",
  });
