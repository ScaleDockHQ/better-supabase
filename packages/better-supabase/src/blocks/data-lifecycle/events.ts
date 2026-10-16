import type {
  DataExportEventData,
  LegalHoldEventData,
  OrganizationDeletionEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `data-lifecycle` block: type to data. */
export type DataLifecycleEvents = {
  readonly "data_export.requested": DataExportEventData;
  readonly "data_export.completed": DataExportEventData;
  readonly "data_export.failed": DataExportEventData;
  readonly "organization.deletion_requested": OrganizationDeletionEventData;
  readonly "organization.deletion_cancelled": OrganizationDeletionEventData;
  readonly "organization.purged": OrganizationDeletionEventData;
  readonly "legal_hold.placed": LegalHoldEventData;
  readonly "legal_hold.released": LegalHoldEventData;
};

/** The `data-lifecycle` block's event types, for its manifest and `onBlockEvent`. */
export const dataLifecycleEvents: Events<DataLifecycleEvents> = defineEvents({
  "data_export.requested": event<DataExportEventData>(),
  "data_export.completed": event<DataExportEventData>(),
  "data_export.failed": event<DataExportEventData>(),
  "organization.deletion_requested": event<OrganizationDeletionEventData>(),
  "organization.deletion_cancelled": event<OrganizationDeletionEventData>(),
  "organization.purged": event<OrganizationDeletionEventData>(),
  "legal_hold.placed": event<LegalHoldEventData>(),
  "legal_hold.released": event<LegalHoldEventData>(),
});
