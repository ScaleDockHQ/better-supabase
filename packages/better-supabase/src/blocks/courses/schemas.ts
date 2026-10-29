import type { EntitySchema } from "../entity-schema.ts";
import type { CourseInput, CourseLessonInput } from "./courses.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `upsert` takes, with the bounds the SQL checks. */
export const courseInputSchema: EntitySchema<CourseInput> =
  entitySchema<CourseInput>({
    title: "CourseInput",
    fields: {
      id: { kind: "uuid", optional: true },
      key: { kind: "string", optional: true, minLength: 1, maxLength: 63 },
      title: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      summary: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 2000,
      },
      status: {
        kind: "enum",
        values: ["draft", "published", "archived"],
        optional: true,
      },
      certificate: { kind: "boolean", optional: true },
      validForMonths: {
        kind: "integer",
        optional: true,
        nullable: true,
        minimum: 1,
        maximum: 240,
      },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set, keyed by database name.",
      },
    },
  });

/** What `saveLesson` takes, with the bounds the SQL checks. */
export const courseLessonInputSchema: EntitySchema<CourseLessonInput> =
  entitySchema<CourseLessonInput>({
    title: "CourseLessonInput",
    fields: {
      id: { kind: "uuid", optional: true },
      moduleId: { kind: "uuid", optional: true },
      title: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      kind: {
        kind: "enum",
        values: ["content", "video", "quiz"],
        optional: true,
      },
      body: {
        kind: "unknown",
        optional: true,
        description: "The lesson's content, such as a rich-text document.",
      },
      mediaUrl: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 2000,
      },
      formId: { kind: "uuid", optional: true, nullable: true },
      required: { kind: "boolean", optional: true },
      minutes: {
        kind: "integer",
        optional: true,
        nullable: true,
        minimum: 1,
        maximum: 10_000,
      },
      rank: { kind: "string", optional: true, minLength: 1 },
    },
  });

/** What the section's `enroll` and `unenroll` writes take. */
export interface CourseLearnerSectionInput {
  /** The learner; the caller when left out. */
  readonly userId?: string;
}

export const courseLearnerSectionInputSchema: EntitySchema<CourseLearnerSectionInput> =
  entitySchema<CourseLearnerSectionInput>({
    title: "CourseLearnerSectionInput",
    fields: { userId: { kind: "uuid", optional: true } },
  });
