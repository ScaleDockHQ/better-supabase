import type { BlockOf } from "../define-block.ts";
import type { SequencesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { sequencesEvents } from "./events.ts";
import { sequenceListSurface } from "./lists.ts";
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
  entities: {
    sequence: {
      ...sequenceListSurface,
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.",
  recipes: ["sequence-builder"],
});
