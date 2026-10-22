import type { BillingEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `billing` block: type to data. */
export type BillingEvents = {
  readonly "billing.customer_linked": BillingEventData;
  readonly "billing.account_linked": BillingEventData;
  readonly "billing.checkout_completed": BillingEventData;
  readonly "billing.subscription_created": BillingEventData;
  readonly "billing.subscription_updated": BillingEventData;
  readonly "billing.subscription_deleted": BillingEventData;
  readonly "billing.seats_synced": BillingEventData;
};

/** The `billing` block's event types, for its manifest and `onBlockEvent`. */
export const billingEvents: Events<BillingEvents> = defineEvents({
  "billing.customer_linked": event<BillingEventData>(),
  "billing.account_linked": event<BillingEventData>(),
  "billing.checkout_completed": event<BillingEventData>(),
  "billing.subscription_created": event<BillingEventData>(),
  "billing.subscription_updated": event<BillingEventData>(),
  "billing.subscription_deleted": event<BillingEventData>(),
  "billing.seats_synced": event<BillingEventData>(),
});
