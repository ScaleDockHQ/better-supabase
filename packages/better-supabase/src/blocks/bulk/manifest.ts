import type { BlockOf } from "../define-block.ts";
import type { BulkEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBulk } from "./bulk.ts";
import { bulkEvents } from "./events.ts";
import { bulkSqlOptions } from "./options.ts";

/** The `bulk` block's manifest (ADR 0029). */
export const bulkBlock: BlockOf<"bulk", typeof createBulk, BulkEvents> =
  defineBlock({
    name: "bulk",
    sql: ["bulk"],
    options: {
      bulk: bulkSqlOptions,
    },
    events: bulkEvents,
    create: createBulk,
    category: "work",
    recipes: ["bulk-action-bar"],
  });
