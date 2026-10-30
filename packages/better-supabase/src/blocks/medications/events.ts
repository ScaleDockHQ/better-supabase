import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The record an order is for and the order's state. */
interface MedicationOrderEventBase {
  readonly organizationId: string;
  readonly medicationOrderId: string;
  readonly medicationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `active`, `paused` or `stopped`. */
  readonly status: string;
}

/** `medication_order.created`: a medication was prescribed or imported. */
export type MedicationOrderCreatedEventData = MedicationOrderEventBase;

/**
 * `medication_order.updated`: the dose, schedule or dates changed, or it
 * resumed.
 */
export type MedicationOrderUpdatedEventData = MedicationOrderEventBase;

/** `medication_order.paused`: no doses are planned until it resumes. */
export type MedicationOrderPausedEventData = MedicationOrderEventBase;

/** `medication_order.stopped`: the order ended for good. */
export interface MedicationOrderStoppedEventData extends MedicationOrderEventBase {
  readonly reason: string;
}

/** A dose and the record it was for. */
interface MedicationAdministrationEventBase {
  readonly organizationId: string;
  readonly medicationOrderId: string;
  readonly medicationAdministrationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `given`, `refused`, `skipped` or `missed`. */
  readonly status: string;
  /** ISO timestamps; `scheduledAt` is null for an as-needed dose. */
  readonly scheduledAt: string | null;
  readonly administeredAt: string | null;
}

/** `medication_administration.recorded`: a dose was given, refused or skipped. */
export type MedicationAdministrationRecordedEventData =
  MedicationAdministrationEventBase;

/** `medication_administration.missed`: a planned dose wasn't recorded in time. */
export type MedicationAdministrationMissedEventData =
  MedicationAdministrationEventBase;

/** The events of the `medications` block: type to data. */
export type MedicationsEvents = {
  readonly "medication_order.created": MedicationOrderCreatedEventData;
  readonly "medication_order.updated": MedicationOrderUpdatedEventData;
  readonly "medication_order.paused": MedicationOrderPausedEventData;
  readonly "medication_order.stopped": MedicationOrderStoppedEventData;
  readonly "medication_administration.recorded": MedicationAdministrationRecordedEventData;
  readonly "medication_administration.missed": MedicationAdministrationMissedEventData;
};

/** The `medications` block's event types, for its manifest and `onBlockEvent`. */
export const medicationsEvents: Events<MedicationsEvents> = defineEvents({
  "medication_order.created": event<MedicationOrderCreatedEventData>(),
  "medication_order.updated": event<MedicationOrderUpdatedEventData>(),
  "medication_order.paused": event<MedicationOrderPausedEventData>(),
  "medication_order.stopped": event<MedicationOrderStoppedEventData>(),
  "medication_administration.recorded":
    event<MedicationAdministrationRecordedEventData>(),
  "medication_administration.missed":
    event<MedicationAdministrationMissedEventData>(),
});
