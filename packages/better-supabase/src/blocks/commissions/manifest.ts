import type { BlockOf } from "../define-block.ts";
import type { CommissionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCommissions } from "./commissions.ts";
import { commissionsEvents } from "./events.ts";
import { commissionsSqlOptions } from "./options.ts";

/** The `commissions` block's manifest. */
export const commissionsBlock: BlockOf<
  "commissions",
  typeof createCommissions,
  CommissionsEvents
> = defineBlock({
  name: "commissions",
  sql: ["commissions"],
  events: commissionsEvents,
  schemas: {},
  options: { commissions: commissionsSqlOptions },
  create: createCommissions,
  recipes: [],
  category: "commerce",
});
