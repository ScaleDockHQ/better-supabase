import type { BlockOf } from "../define-block.ts";
import type { PartiesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { partiesEvents } from "./events.ts";
import { partiesSqlOptions } from "./options.ts";
import { createParties } from "./parties.ts";
import {
  companyInputSchema,
  partyListFilterSchema,
  personInputSchema,
} from "./schemas.ts";

/** The `parties` block's manifest (ADR 0029). */
export const partiesBlock: BlockOf<
  "parties",
  typeof createParties,
  PartiesEvents
> = defineBlock({
  name: "parties",
  sql: ["parties"],
  options: { parties: partiesSqlOptions },
  events: partiesEvents,
  create: createParties,
  category: "crm",
  recipes: ["contact-detail"],
  schemas: {
    company: { input: companyInputSchema, listFilter: partyListFilterSchema },
    person: { input: personInputSchema, listFilter: partyListFilterSchema },
  },
});
