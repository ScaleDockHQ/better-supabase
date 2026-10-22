import type { BlockOf } from "../define-block.ts";
import type { CollectionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCollections } from "./collections.ts";
import { collectionsEvents } from "./events.ts";
import { collectionsSqlOptions } from "./options.ts";

/** The `collections` block's manifest (ADR 0029). */
export const collectionsBlock: BlockOf<
  "collections",
  typeof createCollections,
  CollectionsEvents,
  { readonly notifier: "optional" }
> = defineBlock({
  name: "collections",
  sql: ["collections"],
  options: { collections: collectionsSqlOptions },
  events: collectionsEvents,
  consumes: { notifier: "optional" },
  create: createCollections,
  category: "work",
});
