import type { AiProviderKeyEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `ai-providers` block: type to data. */
export type AiProvidersEvents = {
  readonly "ai_provider_key.saved": AiProviderKeyEventData;
  readonly "ai_provider_key.deleted": AiProviderKeyEventData;
};

/** The `ai-providers` block's event types, for its manifest and `onBlockEvent`. */
export const aiProvidersEvents: Events<AiProvidersEvents> = defineEvents({
  "ai_provider_key.saved": event<AiProviderKeyEventData>(),
  "ai_provider_key.deleted": event<AiProviderKeyEventData>(),
});
