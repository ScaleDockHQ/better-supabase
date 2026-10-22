import type { BlockOf } from "../define-block.ts";
import type { SequencesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { sequencesEvents } from "./events.ts";
import { sequencesSqlOptions } from "./options.ts";
import { sequenceEnrollInputSchema, sequenceInputSchema } from "./schemas.ts";
import { createSequences } from "./sequences.ts";

/** The `sequences` block's manifest (ADR 0029). */
export const sequencesBlock: BlockOf<
  "sequences",
  typeof createSequences,
  SequencesEvents,
  { readonly mailer: "optional" }
> = defineBlock({
  name: "sequences",
  sql: ["sequences"],
  options: { sequences: sequencesSqlOptions },
  events: sequencesEvents,
  consumes: { mailer: "optional" },
  schemas: {
    sequence: { input: sequenceInputSchema },
    sequence_enrollment: { input: sequenceEnrollInputSchema },
  },
  create: createSequences,
  category: "crm",
  recipes: ["sequence-builder"],
});
