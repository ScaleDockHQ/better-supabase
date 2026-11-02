import type {
  DataExportEventData,
  LegalHoldEventData,
  OrganizationDeletionEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The `data_subject_request.*` events. */
export interface DataSubjectRequestEventData {
  readonly requestId: string;
  readonly organizationId: string;
  /** `access`, `erasure`, `rectification` or `portability`. */
  readonly kind: string;
  /** `received`, `verified`, `fulfilled` or `refused`, after the change. */
  readonly status: string;
  readonly dueAt: string;
}

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
  readonly "data_subject_request.received": DataSubjectRequestEventData;
  readonly "data_subject_request.verified": DataSubjectRequestEventData;
  readonly "data_subject_request.extended": DataSubjectRequestEventData;
  readonly "data_subject_request.fulfilled": DataSubjectRequestEventData;
  readonly "data_subject_request.refused": DataSubjectRequestEventData;
};

/**
 * The `data-lifecycle` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const dataLifecycleEvents: Events<DataLifecycleEvents> = defineEvents({
  "data_export.requested": event<DataExportEventData>(),
  "data_export.completed": event<DataExportEventData>(),
  "data_export.failed": event<DataExportEventData>(),
  "organization.deletion_requested": event<OrganizationDeletionEventData>(),
  "organization.deletion_cancelled": event<OrganizationDeletionEventData>(),
  "organization.purged": event<OrganizationDeletionEventData>(),
  "legal_hold.placed": event<LegalHoldEventData>(),
  "legal_hold.released": event<LegalHoldEventData>(),
  "data_subject_request.received": event<DataSubjectRequestEventData>(),
  "data_subject_request.verified": event<DataSubjectRequestEventData>(),
  "data_subject_request.extended": event<DataSubjectRequestEventData>(),
  "data_subject_request.fulfilled": event<DataSubjectRequestEventData>(),
  "data_subject_request.refused": event<DataSubjectRequestEventData>(),
});
