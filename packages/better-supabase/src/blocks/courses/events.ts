import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `course.saved` and `course.deleted`. */
export interface CourseEventData {
  readonly organizationId: string;
  /** The course. */
  readonly id: string;
  readonly key: string;
  readonly status: string;
}

/** `course.enrolled`, `course.unenrolled` and `course.completed`. */
export interface CourseLearnerEventData {
  readonly organizationId: string;
  /** The course. */
  readonly id: string;
  readonly userId: string;
  readonly enrollmentId: string;
}

/** `course_lesson.completed`: a learner finished a lesson. */
export interface CourseLessonCompletedEventData {
  readonly organizationId: string;
  /** The lesson. */
  readonly id: string;
  readonly courseId: string;
  readonly userId: string;
  readonly enrollmentId: string;
}

/** `course_certificate.issued` and `course_certificate.revoked`. */
export interface CourseCertificateEventData {
  readonly organizationId: string;
  /** The certificate. */
  readonly id: string;
  readonly courseId: string;
  readonly userId: string;
  readonly enrollmentId: string;
}

/** `course_certificate.issued`: also when the certificate expires. */
export interface CourseCertificateIssuedEventData extends CourseCertificateEventData {
  /** An ISO timestamp, or null when the certificate never expires. */
  readonly expiresAt: string | null;
}

/** The events of the `courses` block: type to data. */
export type CoursesEvents = {
  readonly "course.saved": CourseEventData;
  readonly "course.deleted": CourseEventData;
  readonly "course.enrolled": CourseLearnerEventData;
  readonly "course.unenrolled": CourseLearnerEventData;
  readonly "course.completed": CourseLearnerEventData;
  readonly "course_lesson.completed": CourseLessonCompletedEventData;
  readonly "course_certificate.issued": CourseCertificateIssuedEventData;
  readonly "course_certificate.revoked": CourseCertificateEventData;
};

/** The `courses` block's event types, for its manifest and `onBlockEvent`. */
export const coursesEvents: Events<CoursesEvents> = defineEvents({
  "course.saved": event<CourseEventData>(),
  "course.deleted": event<CourseEventData>(),
  "course.enrolled": event<CourseLearnerEventData>(),
  "course.unenrolled": event<CourseLearnerEventData>(),
  "course.completed": event<CourseLearnerEventData>(),
  "course_lesson.completed": event<CourseLessonCompletedEventData>(),
  "course_certificate.issued": event<CourseCertificateIssuedEventData>(),
  "course_certificate.revoked": event<CourseCertificateEventData>(),
});
