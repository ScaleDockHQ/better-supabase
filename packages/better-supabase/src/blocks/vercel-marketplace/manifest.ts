import type { BlockOf } from "../define-block.ts";
import type { VercelMarketplaceEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { vercelMarketplaceEvents } from "./events.ts";
import { vercelMarketplaceSqlOptions } from "./options.ts";
import { createVercelMarketplace } from "./vercel-marketplace.ts";

/** The `vercel-marketplace` block's manifest (ADR 0029). */
export const vercelMarketplaceBlock: BlockOf<
  "vercel-marketplace",
  typeof createVercelMarketplace,
  VercelMarketplaceEvents
> = defineBlock({
  name: "vercel-marketplace",
  sql: ["vercel-marketplace"],
  options: {
    "vercel-marketplace": vercelMarketplaceSqlOptions,
  },
  events: vercelMarketplaceEvents,
  create: createVercelMarketplace,
  category: "developer",
});
