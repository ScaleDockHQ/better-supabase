import type { EnrichmentEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `enrichment` block: type to data. */
export type EnrichmentEvents = {
  readonly "company.enriched": EnrichmentEventData;
  readonly "person.enriched": EnrichmentEventData;
};

/** The `enrichment` block's event types, for its manifest and `onBlockEvent`. */
export const enrichmentEvents: Events<EnrichmentEvents> = defineEvents({
  "company.enriched": event<EnrichmentEventData>(),
  "person.enriched": event<EnrichmentEventData>(),
});
