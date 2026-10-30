import type { BlockOf } from "../define-block.ts";
import type { QualificationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { qualificationsEvents } from "./events.ts";
import { qualificationsSqlOptions } from "./options.ts";
import { createQualifications } from "./qualifications.ts";
import {
  qualificationGrantInputSchema,
  qualificationTypeInputSchema,
} from "./schemas.ts";

/** The `qualifications` block's manifest (ADR 0029). */
export const qualificationsBlock: BlockOf<
  "qualifications",
  typeof createQualifications,
  QualificationsEvents
> = defineBlock({
  name: "qualifications",
  sql: ["qualifications"],
  options: { qualifications: qualificationsSqlOptions },
  events: qualificationsEvents,
  schemas: {
    qualification_type: { input: qualificationTypeInputSchema },
    qualification: { input: qualificationGrantInputSchema },
  },
  create: createQualifications,
  recipes: ["qualification-matrix", "my-qualifications"],
  category: "people",
});
