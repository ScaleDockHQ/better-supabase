import type { BlockOf } from "../define-block.ts";
import type { EnrichmentEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEnrichment } from "./enrichment.ts";
import { enrichmentEvents } from "./events.ts";

/** The `enrichment` block's manifest (ADR 0029). */
export const enrichmentBlock: BlockOf<
  "enrichment",
  typeof createEnrichment,
  EnrichmentEvents
> = defineBlock({
  name: "enrichment",
  sql: ["enrichment"],
  events: enrichmentEvents,
  create: createEnrichment,
  category: "crm",
});
