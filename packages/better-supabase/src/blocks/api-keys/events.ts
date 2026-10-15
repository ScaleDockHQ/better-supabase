import type { ApiKeyEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `api-keys` block: type to data. */
export type ApiKeysEvents = {
  readonly "api_key.created": ApiKeyEventData;
  readonly "api_key.revoked": ApiKeyEventData;
  readonly "api_key.rotated": ApiKeyEventData;
};

/** The `api-keys` block's event types, for its manifest and `onBlockEvent`. */
export const apiKeysEvents: Events<ApiKeysEvents> = defineEvents({
  "api_key.created": event<ApiKeyEventData>(),
  "api_key.revoked": event<ApiKeyEventData>(),
  "api_key.rotated": event<ApiKeyEventData>(),
});
