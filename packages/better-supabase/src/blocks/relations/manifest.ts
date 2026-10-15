import type { BlockOf } from "../define-block.ts";
import type { RelationsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { relationsEvents } from "./events.ts";
import { createRelations } from "./relations.ts";

/** The `relations` block's manifest (ADR 0029). */
export const relationsBlock: BlockOf<
  "relations",
  typeof createRelations,
  RelationsEvents
> = defineBlock({
  name: "relations",
  sql: ["relations"],
  options: {
    relations: optionKeys(["kinds", "subjects"]),
  },
  events: relationsEvents,
  create: createRelations,
  category: "work",
});
