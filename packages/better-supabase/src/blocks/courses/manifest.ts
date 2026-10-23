import type { BlockOf } from "../define-block.ts";
import type { CoursesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCourses } from "./courses.ts";
import { coursesEvents } from "./events.ts";
import { coursesSqlOptions } from "./options.ts";
import { courseInputSchema, courseLessonInputSchema } from "./schemas.ts";

/** The `courses` block's manifest (ADR 0029). */
export const coursesBlock: BlockOf<
  "courses",
  typeof createCourses,
  CoursesEvents
> = defineBlock({
  name: "courses",
  sql: ["courses"],
  options: { courses: coursesSqlOptions },
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
  recipes: ["course-outline", "lesson-player"],
});
