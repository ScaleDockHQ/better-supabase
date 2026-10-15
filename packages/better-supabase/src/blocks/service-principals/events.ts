import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `service-principals` block: type to data. */
export type ServicePrincipalsEvents = {
  readonly "service_principal.created": SaasEventData;
  readonly "service_principal.role_changed": SaasEventData;
  readonly "service_principal.disabled": SaasEventData;
};

/** The `service-principals` block's event types, for its manifest and `onBlockEvent`. */
export const servicePrincipalsEvents: Events<ServicePrincipalsEvents> =
  defineEvents({
    "service_principal.created": event<SaasEventData>(),
    "service_principal.role_changed": event<SaasEventData>(),
    "service_principal.disabled": event<SaasEventData>(),
  });
