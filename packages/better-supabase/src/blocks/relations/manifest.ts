import type { BlockOf } from "../define-block.ts";
import type { RelationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { relationsEvents } from "./events.ts";
import { relationsSqlOptions } from "./options.ts";
import { relationsBinding } from "./record-binding.ts";
import { createRelations } from "./relations.ts";

/** The `relations` block's manifest (ADR 0029). */
export const relationsBlock: BlockOf<
  "relations",
  typeof createRelations,
  RelationsEvents,
  Record<never, never>,
  never,
  typeof relationsBinding
> = defineBlock({
  name: "relations",
  sql: ["relations"],
  options: { relations: relationsSqlOptions },
  events: relationsEvents,
  create: createRelations,
  record: relationsBinding,
  category: "work",
  entities: { relation: { mutability: "read-only" } },
  description:
    "Typed links between subjects (blocks, parent, relates, or your own kinds), with inverse names, cycle checks, one-target kinds, walks and rollups.",
  recipes: ["related-items-panel"],
});
