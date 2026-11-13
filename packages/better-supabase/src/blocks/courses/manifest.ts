import type { BlockOf } from "../define-block.ts";
import type { CoursesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCourses } from "./courses.ts";
import { coursesEvents } from "./events.ts";
import { courseInputSchema, courseLessonInputSchema } from "./schemas.ts";

/** The `courses` block's manifest (ADR 0029). */
export const coursesBlock: BlockOf<
  "courses",
  typeof createCourses,
  CoursesEvents
> = defineBlock({
  name: "courses",
  sql: ["courses"],
  events: coursesEvents,
  schemas: {
    course: { input: courseInputSchema },
    course_lesson: { input: courseLessonInputSchema },
  },
  create: createCourses,
  // No record binding: learners are users, and generated record pages attach
  // block bindings to the other subjects. An app's course page mounts
  // courseLearnersBinding itself.
  category: "content",
  entities: {
    course: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    course_module: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
    course_lesson: {
      mutability: "editable",
      emits: { create: false, update: false, delete: false },
    },
    course_certificate: { mutability: "state-machine" },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Courses of modules and lessons ordered by rank keys, with quiz lessons graded by forms, per-lesson progress, completion and certificates. Each course runs as an enrollment program, so learners enroll through enrollments.",
  recipes: ["course-outline", "lesson-player"],
});
