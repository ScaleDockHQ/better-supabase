import type { AiProviderKeyEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `ai-keys` block: type to data. */
export type AiKeysEvents = {
  readonly "ai_provider_key.created": AiProviderKeyEventData;
  readonly "ai_provider_key.updated": AiProviderKeyEventData;
  readonly "ai_provider_key.deleted": AiProviderKeyEventData;
};

/** The `ai-keys` block's event types, for its manifest and `onBlockEvent`. */
export const aiKeysEvents: Events<AiKeysEvents> = defineEvents({
  "ai_provider_key.created": event<AiProviderKeyEventData>(),
  "ai_provider_key.updated": event<AiProviderKeyEventData>(),
  "ai_provider_key.deleted": event<AiProviderKeyEventData>(),
});
