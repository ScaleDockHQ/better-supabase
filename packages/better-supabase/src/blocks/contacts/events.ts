import type { PartyEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";
import type { SupplierStatus } from "./roles.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A company's or person's supplier status changed (`setSupplierStatus`). */
export interface SupplierStatusChangedEventData {
  readonly organizationId: string;
  /** Set on `company.supplier_status_changed`. */
  readonly companyId?: string;
  /** Set on `person.supplier_status_changed`. */
  readonly personId?: string;
  readonly name: string;
  /** The new status; `null` when it was cleared. */
  readonly status: SupplierStatus | null;
  readonly previousStatus: SupplierStatus | null;
  readonly reason: string | null;
}

/** The events of the `parties` block: type to data. */
export type ContactsEvents = {
  readonly "company.created": PartyEventData;
  readonly "company.updated": PartyEventData;
  readonly "company.archived": PartyEventData;
  readonly "company.merged": PartyEventData;
  readonly "company.person_linked": PartyEventData;
  readonly "company.person_unlinked": PartyEventData;
  readonly "company.supplier_status_changed": SupplierStatusChangedEventData;
  readonly "person.created": PartyEventData;
  readonly "person.updated": PartyEventData;
  readonly "person.archived": PartyEventData;
  readonly "person.merged": PartyEventData;
  readonly "person.supplier_status_changed": SupplierStatusChangedEventData;
};

/** The `parties` block's event types, for its manifest and `onBlockEvent`. */
export const contactsEvents: Events<ContactsEvents> = defineEvents({
  "company.created": event<PartyEventData>(),
  "company.updated": event<PartyEventData>(),
  "company.archived": event<PartyEventData>(),
  "company.merged": event<PartyEventData>(),
  "company.person_linked": event<PartyEventData>(),
  "company.person_unlinked": event<PartyEventData>(),
  "company.supplier_status_changed": event<SupplierStatusChangedEventData>(),
  "person.created": event<PartyEventData>(),
  "person.updated": event<PartyEventData>(),
  "person.archived": event<PartyEventData>(),
  "person.merged": event<PartyEventData>(),
  "person.supplier_status_changed": event<SupplierStatusChangedEventData>(),
});
