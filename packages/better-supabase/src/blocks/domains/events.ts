import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `hostname.*`: which organization's hostname changed. */
export interface HostnameEventData {
  readonly organizationId: string;
  readonly hostnameId: string;
  readonly hostname: string;
}

/** The events of the `domains` block: type to data. */
export type DomainsEvents = {
  readonly "hostname.added": HostnameEventData;
  readonly "hostname.verified": HostnameEventData;
  readonly "hostname.primary_set": HostnameEventData;
  readonly "hostname.removed": HostnameEventData;
};

/** The `domains` block's event types, for its manifest and `onBlockEvent`. */
export const domainsEvents: Events<DomainsEvents> = defineEvents({
  "hostname.added": event<HostnameEventData>(),
  "hostname.verified": event<HostnameEventData>(),
  "hostname.primary_set": event<HostnameEventData>(),
  "hostname.removed": event<HostnameEventData>(),
});
