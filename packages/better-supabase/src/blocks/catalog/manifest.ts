import type { BlockOf } from "../define-block.ts";
import type { CatalogEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCatalog } from "./catalog.ts";
import { catalogEvents } from "./events.ts";
import { catalogSqlOptions } from "./options.ts";

/** The `catalog` block's manifest (ADR 0029). */
export const catalogBlock: BlockOf<
  "catalog",
  typeof createCatalog,
  CatalogEvents
> = defineBlock({
  name: "catalog",
  sql: ["catalog"],
  options: {
    catalog: catalogSqlOptions,
  },
  events: catalogEvents,
  create: createCatalog,
  category: "commerce",
});
