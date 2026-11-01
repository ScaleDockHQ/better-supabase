import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `prescription.*` event carries. */
export interface PrescriptionEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The medication order the prescription is for. */
  readonly orderId: string;
  /** The record the prescription is about, any registered subject. */
  readonly subjectType: string;
  readonly subjectId: string;
  /** `draft`, `signed`, `sent`, `dispensed` or `cancelled`. */
  readonly status: string;
}

/** The events of the `e-prescribing` block: type to data. */
export type EPrescribingEvents = {
  readonly "prescription.created": PrescriptionEventData;
  readonly "prescription.signed": PrescriptionEventData;
  readonly "prescription.sent": PrescriptionEventData;
  readonly "prescription.delivery_failed": PrescriptionEventData;
  readonly "prescription.dispensed": PrescriptionEventData;
  readonly "prescription.cancelled": PrescriptionEventData;
};

/** The `e-prescribing` block's event types, for its manifest and `onBlockEvent`. */
export const ePrescribingEvents: Events<EPrescribingEvents> = defineEvents({
  "prescription.created": event<PrescriptionEventData>(),
  "prescription.signed": event<PrescriptionEventData>(),
  "prescription.sent": event<PrescriptionEventData>(),
  "prescription.delivery_failed": event<PrescriptionEventData>(),
  "prescription.dispensed": event<PrescriptionEventData>(),
  "prescription.cancelled": event<PrescriptionEventData>(),
});
