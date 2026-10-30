import type { CredentialEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `credentials` block: type to data. */
export type CredentialsEvents = {
  readonly "credential.updated": CredentialEventData;
  readonly "credential.deleted": CredentialEventData;
};

/** The `credentials` block's event types, for its manifest and `onBlockEvent`. */
export const credentialsEvents: Events<CredentialsEvents> = defineEvents({
  "credential.updated": event<CredentialEventData>(),
  "credential.deleted": event<CredentialEventData>(),
});
