import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `enrollment_program.created`, `enrollment_program.updated` and
 * `enrollment_program.deleted`.
 */
export interface EnrollmentProgramEventData {
  readonly organizationId: string;
  /** The program. */
  readonly id: string;
  readonly key: string;
  readonly version: number;
}

/**
 * `enrollment.created`, `enrollment.step_completed`, `enrollment.completed` and
 * `enrollment.cancelled`. Only enrollments in an organization emit them, so a
 * user's own onboarding checklist doesn't.
 */
export interface EnrollmentEventData {
  readonly organizationId: string;
  /** The enrollment. */
  readonly id: string;
  /** The program key; `onboarding:<checklist>` for an onboarding checklist. */
  readonly program: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly status: "active" | "completed" | "cancelled";
  /** The step, for `enrollment.step_completed`. */
  readonly step: string | null;
  readonly completedSteps: number;
  readonly totalSteps: number;
}

/** The events of the `enrollments` block: type to data. */
export type EnrollmentsEvents = {
  readonly "enrollment_program.created": EnrollmentProgramEventData;
  readonly "enrollment_program.updated": EnrollmentProgramEventData;
  readonly "enrollment_program.deleted": EnrollmentProgramEventData;
  readonly "enrollment.created": EnrollmentEventData;
  readonly "enrollment.step_completed": EnrollmentEventData;
  readonly "enrollment.completed": EnrollmentEventData;
  readonly "enrollment.cancelled": EnrollmentEventData;
};

/** The `enrollments` block's event types, for its manifest and `onBlockEvent`. */
export const enrollmentsEvents: Events<EnrollmentsEvents> = defineEvents({
  "enrollment_program.created": event<EnrollmentProgramEventData>(),
  "enrollment_program.updated": event<EnrollmentProgramEventData>(),
  "enrollment_program.deleted": event<EnrollmentProgramEventData>(),
  "enrollment.created": event<EnrollmentEventData>(),
  "enrollment.step_completed": event<EnrollmentEventData>(),
  "enrollment.completed": event<EnrollmentEventData>(),
  "enrollment.cancelled": event<EnrollmentEventData>(),
});
