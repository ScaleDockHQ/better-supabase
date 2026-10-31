import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What `legal_entity.created` and `legal_entity.updated` carry. */
export interface LegalEntityEventData {
  readonly organizationId: string;
  /** The legal entity. */
  readonly legalEntityId: string;
  readonly code: string;
  /** Whether it is the organization's default entity after the change. */
  readonly isDefault: boolean;
}

/** The events of the `legal-entities` block: type to data. */
export type LegalEntitiesEvents = {
  readonly "legal_entity.created": LegalEntityEventData;
  readonly "legal_entity.updated": LegalEntityEventData;
};

/**
 * The `legal-entities` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const legalEntitiesEvents: Events<LegalEntitiesEvents> = defineEvents({
  "legal_entity.created": event<LegalEntityEventData>(),
  "legal_entity.updated": event<LegalEntityEventData>(),
});
