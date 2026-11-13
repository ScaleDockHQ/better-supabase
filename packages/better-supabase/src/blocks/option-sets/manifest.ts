import type { BlockOf } from "../define-block.ts";
import type { OptionSetsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { optionSetsEvents } from "./events.ts";
import { createOptionSets } from "./option-sets.ts";
import { optionSetsSqlOptions } from "./options.ts";

/** The `option-sets` block's manifest (ADR 0029). */
export const optionSetsBlock: BlockOf<
  "option-sets",
  typeof createOptionSets,
  OptionSetsEvents
> = defineBlock({
  name: "option-sets",
  sql: ["option-sets"],
  options: { "option-sets": optionSetsSqlOptions },
  events: optionSetsEvents,
  create: createOptionSets,
  category: "work",
  entities: {
    option_set: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Tenant-editable items for a field such as priority or severity: ordered items with a label, color, icon and a level the record keeps in its own column, replacement when an item is removed, and starter items per brand.",
});
