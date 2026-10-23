import type { RecordBinding, RecordBindingWrite } from "../record-bindings.ts";
import type { CourseLearner, Courses } from "./courses.ts";
import type { CourseLearnerSectionInput } from "./schemas.ts";

import { defineRecordBinding } from "../record-bindings.ts";
import { courseLearnerSectionInputSchema } from "./schemas.ts";

/** The writes of the course learners binding. */
export type CourseLearnersWrites = {
  /** Enrolls a learner, or the caller, in the course. */
  readonly enroll: RecordBindingWrite<
    Courses,
    CourseLearnerSectionInput,
    CourseLearner
  >;
  /** Cancels a learner's enrollment; their progress stays. */
  readonly unenroll: RecordBindingWrite<
    Courses,
    CourseLearnerSectionInput,
    CourseLearner
  >;
};

/** A course's learners with their progress, on the course's page. */
export const courseLearnersBinding: RecordBinding<
  Courses,
  readonly CourseLearner[],
  undefined,
  never,
  CourseLearnersWrites
> = defineRecordBinding({
  permissions: { read: "enroll", write: "enroll" },
  module: "courses",
  load: (client: Courses, subject) => client.learners(subject.id),
  events: ["course.*", "course_lesson.*", "course_certificate.*"],
  writes: {
    enroll: {
      input: courseLearnerSectionInputSchema,
      run: (client: Courses, subject, { userId }: CourseLearnerSectionInput) =>
        client.enroll(subject.id, userId),
    },
    unenroll: {
      input: courseLearnerSectionInputSchema,
      run: (client: Courses, subject, { userId }: CourseLearnerSectionInput) =>
        client.unenroll(subject.id, userId),
    },
  },
});
