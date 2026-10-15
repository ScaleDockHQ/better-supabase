import type { ConnectorEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `connectors` block: type to data. */
export type ConnectorsEvents = {
  readonly "connector.saved": ConnectorEventData;
  readonly "connector.deleted": ConnectorEventData;
  readonly "connector.fingerprint_decided": ConnectorEventData;
  readonly "connector_grant.created": ConnectorEventData;
  readonly "connector_grant.revoked": ConnectorEventData;
};

/** The `connectors` block's event types, for its manifest and `onBlockEvent`. */
export const connectorsEvents: Events<ConnectorsEvents> = defineEvents({
  "connector.saved": event<ConnectorEventData>(),
  "connector.deleted": event<ConnectorEventData>(),
  "connector.fingerprint_decided": event<ConnectorEventData>(),
  "connector_grant.created": event<ConnectorEventData>(),
  "connector_grant.revoked": event<ConnectorEventData>(),
});
