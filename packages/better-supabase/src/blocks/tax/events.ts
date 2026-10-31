import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What `tax_code.created` and `tax_code.updated` carry. */
export interface TaxCodeEventData {
  readonly organizationId: string;
  /** The tax code. */
  readonly id: string;
  readonly code: string;
  readonly type: string;
  /** The legal entity the code belongs to, or null for the whole organization. */
  readonly legalEntityId: string | null;
}

/** `tax_return.prepared`: a return's totals were built or rebuilt. */
export interface TaxReturnPreparedEventData {
  readonly organizationId: string;
  /** The tax return. */
  readonly id: string;
  readonly period: string;
  /** `YYYY-MM-DD`. */
  readonly periodStart: string;
  /** `YYYY-MM-DD`. */
  readonly periodEnd: string;
  readonly legalEntityId: string | null;
  /** Sales tax less purchase tax, in minor units as decimal text. */
  readonly netTax: string;
  readonly currency: string | null;
}

/** The events of the `tax` block: type to data. */
export type TaxEvents = {
  readonly "tax_code.created": TaxCodeEventData;
  readonly "tax_code.updated": TaxCodeEventData;
  readonly "tax_return.prepared": TaxReturnPreparedEventData;
};

/** The `tax` block's event types, for its manifest and `onBlockEvent`. */
export const taxEvents: Events<TaxEvents> = defineEvents({
  "tax_code.created": event<TaxCodeEventData>(),
  "tax_code.updated": event<TaxCodeEventData>(),
  "tax_return.prepared": event<TaxReturnPreparedEventData>(),
});
