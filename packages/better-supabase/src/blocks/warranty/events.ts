import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `warranty_claim.*` event carries. */
export interface WarrantyClaimEventData {
  readonly organizationId: string;
  /** The claim. */
  readonly id: string;
  readonly title: string;
  /** The asset the claim covers. */
  readonly assetId: string;
  /** `draft`, `submitted`, `approved`, `denied` or `closed`. */
  readonly status: string;
}

/** `warranty_claim.decided`: the status and the decision text. */
export interface WarrantyClaimDecidedEventData extends WarrantyClaimEventData {
  /** Why the claim was approved or denied. */
  readonly decision: string;
}

/** The events of the `warranty` block: type to data. */
export type WarrantyEvents = {
  readonly "warranty_claim.created": WarrantyClaimEventData;
  readonly "warranty_claim.submitted": WarrantyClaimEventData;
  readonly "warranty_claim.decided": WarrantyClaimDecidedEventData;
  readonly "warranty_claim.closed": WarrantyClaimEventData;
};

/** The `warranty` block's event types, for its manifest and `onBlockEvent`. */
export const warrantyEvents: Events<WarrantyEvents> = defineEvents({
  "warranty_claim.created": event<WarrantyClaimEventData>(),
  "warranty_claim.submitted": event<WarrantyClaimEventData>(),
  "warranty_claim.decided": event<WarrantyClaimDecidedEventData>(),
  "warranty_claim.closed": event<WarrantyClaimEventData>(),
});
