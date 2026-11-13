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
  entities: {
    enrichment: { mutability: "append-only", emits: { create: false } },
  },
  concerns: ["lifecycle"],
  description:
    "Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.",
  providers: [
    {
      option: "provider",
      type: "EnrichmentProvider",
      from: "better-supabase/blocks/enrichment",
      required: true,
      description: "Looks companies and people up.",
      example:
        'peopleDataLabsEnrichment({ apiKey: process.env["PDL_API_KEY"] ?? "" })',
    },
  ],
});
