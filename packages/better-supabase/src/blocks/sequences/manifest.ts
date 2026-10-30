import type { BlockOf } from "../define-block.ts";
import type { SequencesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { sequencesEvents } from "./events.ts";
import { sequencesSqlOptions } from "./options.ts";
import { sequenceInputSchema } from "./schemas.ts";
import { createSequences } from "./sequences.ts";

/** The `sequences` block's manifest (ADR 0029). */
export const sequencesBlock: BlockOf<
  "sequences",
  typeof createSequences,
  SequencesEvents,
  { readonly mailer: "optional" }
> = defineBlock({
  name: "sequences",
  schedules: [
    {
      name: "run-due",
      cron: "* * * * *",
      runs: "runDue()",
      description:
        "Sends the due steps of every active enrollment and moves each to its next wait.",
    },
  ],
  sql: ["sequences"],
  options: { sequences: sequencesSqlOptions },
  events: sequencesEvents,
  consumes: { mailer: "optional" },
  schemas: { sequence: { input: sequenceInputSchema } },
  create: createSequences,
  category: "crm",
  recipes: ["sequence-builder"],
});
