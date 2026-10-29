import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, SERVICE_CALLER, withExtraFields } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The keys `course_json` returns next to the extra columns. */
export const COURSE_KEYS = [
  "id",
  "organizationId",
  "key",
  "title",
  "summary",
  "status",
  "certificate",
  "validForMonths",
  "createdBy",
  "createdAt",
  "updatedAt",
  "fields",
] as const;

/** The enrollments courses run on, checked to be managed. */
export function courseEnrollments(ctx: BlockSqlContext): BlockSqlContext {
  const enrolled = ctx.of("enrollments");

  if (!enrolled.manages) {
    throw new TypeError(
      "blocks.courses: each course runs as an enrollment program, so install enrollments in managed mode",
    );
  }

  return enrolled;
}

/** The SQL pieces the courses function files share. */
export interface CourseSql {
  readonly fn: (name: string) => string;
  readonly c: (column: string) => string;
  readonly m: (column: string) => string;
  readonly l: (column: string) => string;
  readonly p: (column: string) => string;
  readonly k: (column: string) => string;
  readonly e: (column: string) => string;
  readonly courses: string;
  readonly modules: string;
  readonly lessons: string;
  readonly progress: string;
  readonly certificates: string;
  /**
   * The `on conflict` target of a progress entry: its primary key, or the
   * module's unique index over the app's table.
   */
  readonly progressTarget: string;
  /** The `on conflict` target of the one certificate per enrollment. */
  readonly certificateTarget: string;
  /**
   * Column `column` of row `row` in logical table `table`, or `fallback` when
   * the app's table lacks it.
   */
  readonly field: (
    table: string,
    row: string,
    column: string,
    fallback?: string,
  ) => string;
  readonly enrollments: string;
  readonly enrolled: BlockSqlContext;
  readonly read: string;
  readonly enroll: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly courseMissing: string;
  readonly lessonMissing: string;
  readonly courseJson: (row: string) => string;
  readonly program: (course: string) => string;
  /**
   * Records a learner event from `v_enrollment`, a record of id, tenant, course
   * and learner.
   */
  readonly learnerRecord: (type: string, summary: string) => string;
}

/** The names and helpers both courses function files build on. */
export function courseSql(ctx: BlockSqlContext): CourseSql {
  const enrolled = courseEnrollments(ctx);
  const c = (column: string): string => ctx.col("courses", column);
  const keys = moduleOperations("courses");
  const extras = ctx.extraColumns("courses", COURSE_KEYS);

  const field = (
    table: string,
    row: string,
    column: string,
    fallback = "null",
  ): string =>
    ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : fallback;

  const target = (logical: string, suffix: string, columns: string[]) =>
    ctx.owns(logical)
      ? `on constraint ${sqlIdent(`${ctx.tableName(logical).name}_${suffix}`)}`
      : `(${columns.map((column) => ctx.col(logical, column)).join(", ")})`;

  return {
    fn: (name) => ctx.fn(name),
    c,
    m: (column) => ctx.col("modules", column),
    l: (column) => ctx.col("lessons", column),
    p: (column) => ctx.col("progress", column),
    k: (column) => ctx.col("certificates", column),
    e: (column) => enrolled.col("enrollments", column),
    courses: ctx.table("courses"),
    modules: ctx.table("modules"),
    lessons: ctx.table("lessons"),
    progress: ctx.table("progress"),
    certificates: ctx.table("certificates"),
    progressTarget: target("progress", "pkey", ["enrollment", "lesson"]),
    certificateTarget: target("certificates", "enrollment_key", ["enrollment"]),
    field,
    enrollments: enrolled.table("enrollments"),
    enrolled,
    read: ctx.permission("read", keys.read),
    enroll: ctx.permission("enroll", keys.enroll),
    manage: ctx.permission("manage", keys.manage),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("COURSE_INVALID", message, "22023"),
    forbidden: (message) => fail("COURSE_FORBIDDEN", message),
    courseMissing: fail("COURSE_NOT_FOUND", "course not found", "P0002"),
    lessonMissing: fail(
      "COURSE_LESSON_NOT_FOUND",
      "course lesson not found",
      "P0002",
    ),
    courseJson: (row) =>
      withExtraFields(
        `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'key', ${row}.${c("key")}, 'title', ${row}.${c("title")}, 'summary', ${field("courses", row, "summary")}, 'status', ${row}.${c("status")}, 'certificate', ${field("courses", row, "certificate", "true")}, 'validForMonths', ${field("courses", row, "validForMonths")}, 'createdBy', ${field("courses", row, "createdBy")}, 'createdAt', ${field("courses", row, "createdAt")}, 'updatedAt', ${field("courses", row, "updatedAt")})`,
        row,
        extras,
      ),
    program: (course) => `('course:' || ${course}::text)`,
    learnerRecord: (type, summary) =>
      ctx.record({
        type,
        payload:
          "jsonb_build_object('organizationId', v_enrollment.tenant, 'id', v_enrollment.course, 'userId', v_enrollment.learner, 'enrollmentId', v_enrollment.id)",
        subject: "'courses/' || v_enrollment.course::text",
        tenant: "v_enrollment.tenant",
        audit: {
          category: "data",
          targetType: "course",
          recordId: "v_enrollment.course::text",
          targetLabel: "v_enrollment.learner::text",
          summary: `'${summary}'`,
        },
      }),
  };
}
