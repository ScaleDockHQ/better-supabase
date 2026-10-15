import type { Events, PartyEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `parties` block: type to data. */
export type PartiesEvents = {
  readonly "company.created": PartyEventData;
  readonly "company.updated": PartyEventData;
  readonly "company.archived": PartyEventData;
  readonly "company.merged": PartyEventData;
  readonly "company.person_linked": PartyEventData;
  readonly "company.person_unlinked": PartyEventData;
  readonly "person.created": PartyEventData;
  readonly "person.updated": PartyEventData;
  readonly "person.archived": PartyEventData;
  readonly "person.merged": PartyEventData;
};

/** The `parties` block's event types, for its manifest and `onBlockEvent`. */
export const partiesEvents: Events<PartiesEvents> = defineEvents({
  "company.created": event<PartyEventData>(),
  "company.updated": event<PartyEventData>(),
  "company.archived": event<PartyEventData>(),
  "company.merged": event<PartyEventData>(),
  "company.person_linked": event<PartyEventData>(),
  "company.person_unlinked": event<PartyEventData>(),
  "person.created": event<PartyEventData>(),
  "person.updated": event<PartyEventData>(),
  "person.archived": event<PartyEventData>(),
  "person.merged": event<PartyEventData>(),
});
