import type { BlockOf } from "../define-block.ts";
import type { PartiesEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { partiesEvents } from "./events.ts";
import { createParties } from "./parties.ts";

/** The `parties` block's manifest (ADR 0029). */
export const partiesBlock: BlockOf<
  "parties",
  typeof createParties,
  PartiesEvents
> = defineBlock({
  name: "parties",
  sql: ["parties"],
  options: {
    parties: optionKeys([
      "companyLifecycles",
      "personLifecycles",
      "extraColumns",
    ]),
  },
  events: partiesEvents,
  create: createParties,
  category: "crm",
});
