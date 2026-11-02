import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type {
  FormDefinition,
  FormJsonSchema,
} from "../../core/contracts/form-definition.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { isFormDefinition } from "../../core/contracts/form-definition.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

const COURSE_STATUSES = ["draft", "published", "archived"] as const;
const LESSON_KINDS = ["content", "video", "quiz"] as const;
const LEARNER_STATUSES = ["active", "completed", "cancelled"] as const;

/** Readers see published courses; managers see every status. */
export type CourseStatus = (typeof COURSE_STATUSES)[number];

/** A quiz lesson is graded by a form of the `forms` block. */
export type CourseLessonKind = (typeof LESSON_KINDS)[number];

/** Where a learner's enrollment in a course stands. */
export type CourseLearnerStatus = (typeof LEARNER_STATUSES)[number];

/** A course. `F` types the extra columns the `fields` schema describes. */
export interface Course<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** Unique in the organization. */
  readonly key: string;
  readonly title: string;
  readonly summary?: string;
  readonly status: CourseStatus;
  /** Whether completing the course issues a certificate. */
  readonly certificate: boolean;
  /** How many months a certificate stays valid; without it, it never expires. */
  readonly validForMonths?: number;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** A course to create (without `id`) or change (with it). */
export interface CourseInput<F extends object = Record<never, never>> {
  readonly id?: string;
  readonly key?: string;
  readonly title?: string;
  readonly summary?: string | null;
  readonly status?: CourseStatus;
  readonly certificate?: boolean;
  /** 1 to 240 months a certificate stays valid; `null` for no expiry. */
  readonly validForMonths?: number | null;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** A module of a course: a group of lessons. */
export interface CourseModule {
  readonly id: string;
  readonly courseId: string;
  readonly title: string;
  /** Its fractional rank key (ADR 0021): modules sort by it. */
  readonly rank: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface CourseModuleInput {
  readonly id?: string;
  readonly title?: string;
  /** A rank key; a new module without one goes last. */
  readonly rank?: string;
}

/** A lesson with its content, as managers save it. */
export interface CourseLesson {
  readonly id: string;
  readonly courseId: string;
  readonly moduleId: string;
  readonly title: string;
  readonly kind: CourseLessonKind;
  /** The content, such as a rich-text document. */
  readonly body?: unknown;
  readonly mediaUrl?: string;
  /** The form that grades a quiz lesson. */
  readonly formId?: string;
  /** Required lessons count toward completing the course. */
  readonly required: boolean;
  readonly minutes?: number;
  readonly rank: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface CourseLessonInput {
  readonly id?: string;
  readonly moduleId?: string;
  readonly title?: string;
  readonly kind?: CourseLessonKind;
  readonly body?: unknown;
  readonly mediaUrl?: string | null;
  readonly formId?: string | null;
  readonly required?: boolean;
  readonly minutes?: number | null;
  /** A rank key; a lesson without one goes last in its module. */
  readonly rank?: string;
}

/** A learner's state in one lesson. */
export interface LessonProgress {
  readonly lessonId: string;
  readonly startedAt: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  /** Quiz submissions so far. */
  readonly attempts: number;
  readonly submissionId?: string;
  readonly score?: number;
  readonly maxScore?: number;
  readonly passed?: boolean;
}

/** A certificate for a completed course. */
export interface CourseCertificate {
  readonly id: string;
  readonly courseId: string;
  readonly userId: string;
  /** The random value a verification link carries. */
  readonly code: string;
  readonly issuedAt: Temporal.Instant;
  /** When the certificate expires, from the course's `validForMonths`. */
  readonly expiresAt?: Temporal.Instant;
  readonly revokedAt?: Temporal.Instant;
}

/** A learner's progress in a course. */
export interface CourseLearner {
  readonly enrollmentId: string;
  readonly courseId: string;
  readonly organizationId: string;
  readonly userId: string;
  readonly status: CourseLearnerStatus;
  /** Completed required lessons. */
  readonly completedLessons: number;
  /** Required lessons. */
  readonly totalLessons: number;
  readonly lessons: readonly LessonProgress[];
  readonly certificate?: CourseCertificate;
  readonly enrolledAt: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A lesson in an outline: no content, with the caller's completion. */
export interface CourseOutlineLesson {
  readonly id: string;
  readonly moduleId: string;
  readonly title: string;
  readonly kind: CourseLessonKind;
  readonly required: boolean;
  readonly minutes?: number;
  readonly rank: string;
  readonly completedAt?: Temporal.Instant;
}

export interface CourseOutlineModule {
  readonly id: string;
  readonly title: string;
  readonly rank: string;
  readonly lessons: readonly CourseOutlineLesson[];
}

/** A course with its modules and lessons in order, and the caller's progress. */
export interface CourseOutline<
  F extends object = Record<never, never>,
> extends Course<F> {
  readonly modules: readonly CourseOutlineModule[];
  /** Unset when the caller isn't enrolled. */
  readonly progress?: CourseLearner;
}

/** A quiz lesson's form, without its answer key. */
export interface CourseQuiz {
  readonly formId: string;
  readonly title: string;
  readonly status: string;
  readonly versionId?: string;
  /** The form definition the answers follow, without points or answers. */
  readonly definition?: FormDefinition;
  /** The JSON Schema the answers must match. */
  readonly schema?: FormJsonSchema;
}

/** A lesson as the player shows it. */
export interface CourseLessonView extends CourseLesson {
  readonly quiz?: CourseQuiz;
  readonly progress?: LessonProgress;
}

/** What `submitQuiz` returns. */
export interface CourseQuizResult {
  /** The forms submission, with its score. */
  readonly submission: Readonly<Record<string, unknown>>;
  /** Whether it completed the lesson. */
  readonly passed: boolean;
  readonly progress: CourseLearner;
}

/** What `verifyCertificate` returns for a known code. */
export interface CourseCertificateCheck {
  readonly id: string;
  readonly courseId: string;
  readonly courseTitle: string;
  readonly organizationId: string;
  readonly issuedAt: Temporal.Instant;
  readonly expiresAt?: Temporal.Instant;
  readonly revokedAt?: Temporal.Instant;
  /** True once `expiresAt` has passed. */
  readonly expired: boolean;
  /** Neither revoked nor expired. */
  readonly valid: boolean;
}

export interface CourseLearnersFilter {
  readonly status?: CourseLearnerStatus;
  /** Default 50, at most 200. */
  readonly pageSize?: number;
  /** Learners changed before this instant, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface Courses<F extends object = Record<never, never>> {
  /** Creates or changes a course. */
  upsert(course: CourseInput<F>): AsyncResult<Course<F>>;
  /** The organization's courses by title; readers get the published ones. */
  list(options?: {
    readonly status?: CourseStatus;
  }): AsyncResult<readonly Course<F>[]>;
  /** Deletes a course with its enrollments; `false` when it was gone. */
  delete(courseId: string): AsyncResult<boolean>;
  /** The course with its modules and lessons in rank order. */
  outline(courseId: string): AsyncResult<CourseOutline<F>>;
  saveModule(input: {
    courseId: string;
    module: CourseModuleInput;
  }): AsyncResult<CourseModule>;
  /** Deletes a module with its lessons; `false` when it was gone. */
  deleteModule(moduleId: string): AsyncResult<boolean>;
  saveLesson(input: {
    courseId: string;
    lesson: CourseLessonInput;
  }): AsyncResult<CourseLesson>;
  deleteLesson(lessonId: string): AsyncResult<boolean>;
  /** A lesson with its content and quiz, for managers and enrolled learners. */
  lesson(lessonId: string): AsyncResult<CourseLessonView>;
  /**
   * Enrolls the caller, or `userId` with `courses.enroll`, in a published
   * course. A cancelled enrollment starts again with its completed lessons.
   */
  enroll(input: {
    courseId: string;
    userId?: string | undefined;
  }): AsyncResult<CourseLearner>;
  /** Cancels an active enrollment; its progress stays. */
  unenroll(input: {
    courseId: string;
    userId?: string | undefined;
  }): AsyncResult<CourseLearner>;
  /** Records that the caller opened a lesson. */
  start(lessonId: string): AsyncResult<LessonProgress>;
  /** Marks a content or video lesson done for the caller. */
  complete(lessonId: string): AsyncResult<CourseLearner>;
  /** Marks a lesson not done again. */
  reset(lessonId: string): AsyncResult<CourseLearner>;
  /**
   * Submits answers to a quiz lesson. The database grades them; a passed
   * submission completes the lesson.
   */
  submitQuiz(input: {
    lessonId: string;
    answers: Readonly<Record<string, unknown>>;
  }): AsyncResult<CourseQuizResult>;
  /** The caller's progress, or another user's; `null` when not enrolled. */
  progress(input: {
    courseId: string;
    userId?: string | undefined;
  }): AsyncResult<CourseLearner | null>;
  /** The course's learners, most recently changed first. */
  learners(input: {
    courseId: string;
    filter?: CourseLearnersFilter | undefined;
  }): AsyncResult<readonly CourseLearner[]>;
  /** Checks a certificate by its code; `null` for an unknown code. */
  verifyCertificate(code: string): AsyncResult<CourseCertificateCheck | null>;
  /** Revokes a certificate; `false` when it already was. */
  revokeCertificate(certificateId: string): AsyncResult<boolean>;
  /**
   * Creates the course, its modules and their lessons in order, and returns the
   * outline. It stops at the first failure and leaves what it saved.
   */
  createFromOutline(input: {
    course: CourseInput<F>;
    modules: readonly {
      readonly title: string;
      readonly lessons?: readonly Omit<CourseLessonInput, "moduleId">[];
    }[];
  }): AsyncResult<CourseOutline<F>>;
  /** `upsert` with `status: "published"`. */
  publish(courseId: string): AsyncResult<Course<F>>;
}

export interface CoursesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the course's extra columns
   * (`blocks.courses.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `upsert`.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Courses<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): Partial<Record<K, V>> {
  if (value === undefined) {
    return {};
  }

  const out: Partial<Record<K, V>> = {};
  out[key] = value;

  return out;
}

const numberOr = (value: unknown): number | undefined =>
  typeof value === "number"
    ? value
    : typeof value === "string" && value !== ""
      ? Number(value)
      : undefined;

const booleanOr = (value: unknown): boolean | undefined =>
  typeof value === "boolean" ? value : undefined;

function courseOf(value: unknown, fn: string): Course {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], COURSE_STATUSES, "course status"),
    certificate: row["certificate"] !== false,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...optional("summary", optionalText(row["summary"])),
    ...optional("validForMonths", numberOr(row["validForMonths"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function moduleOf(value: unknown, fn: string): CourseModule {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    courseId: textOf(row["courseId"]),
    title: textOf(row["title"]),
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function lessonOf(value: unknown, fn: string): CourseLesson {
  const row = recordOf(value, fn);
  const body = row["body"];

  return {
    id: textOf(row["id"]),
    courseId: textOf(row["courseId"]),
    moduleId: textOf(row["moduleId"]),
    title: textOf(row["title"]),
    kind: enumOrThrow(row["kind"], LESSON_KINDS, "course lesson kind"),
    required: row["required"] !== false,
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("body", body === null ? undefined : body),
    ...optional("mediaUrl", optionalText(row["mediaUrl"])),
    ...optional("formId", optionalText(row["formId"])),
    ...optional("minutes", numberOr(row["minutes"])),
  };
}

function entryOf(value: unknown, fn: string): LessonProgress {
  const row = recordOf(value, fn);

  return {
    lessonId: textOf(row["lessonId"]),
    startedAt: requiredInstant(row["startedAt"], "startedAt"),
    attempts: Number(row["attempts"] ?? 0),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("submissionId", optionalText(row["submissionId"])),
    ...optional("score", numberOr(row["score"])),
    ...optional("maxScore", numberOr(row["maxScore"])),
    ...optional("passed", booleanOr(row["passed"])),
  };
}

function certificateOf(value: unknown, fn: string): CourseCertificate {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    courseId: textOf(row["courseId"]),
    userId: textOf(row["userId"]),
    code: textOf(row["code"]),
    issuedAt: requiredInstant(row["issuedAt"], "issuedAt"),
    ...optional("expiresAt", optionalInstant(row["expiresAt"])),
    ...optional("revokedAt", optionalInstant(row["revokedAt"])),
  };
}

function learnerOf(value: unknown, fn: string): CourseLearner {
  const row = recordOf(value, fn);

  return {
    enrollmentId: textOf(row["enrollmentId"]),
    courseId: textOf(row["courseId"]),
    organizationId: textOf(row["organizationId"]),
    userId: textOf(row["userId"]),
    status: enumOrThrow(row["status"], LEARNER_STATUSES, "learner status"),
    completedLessons: Number(row["completedLessons"] ?? 0),
    totalLessons: Number(row["totalLessons"] ?? 0),
    lessons: recordsOf(row["lessons"] ?? [], fn).map((item) =>
      entryOf(item, fn),
    ),
    enrolledAt: requiredInstant(row["enrolledAt"], "enrolledAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional(
      "certificate",
      isRecord(row["certificate"])
        ? certificateOf(row["certificate"], fn)
        : undefined,
    ),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("cancelledAt", optionalInstant(row["cancelledAt"])),
  };
}

function outlineLessonOf(value: unknown, fn: string): CourseOutlineLesson {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    moduleId: textOf(row["moduleId"]),
    title: textOf(row["title"]),
    kind: enumOrThrow(row["kind"], LESSON_KINDS, "course lesson kind"),
    required: row["required"] !== false,
    rank: textOf(row["rank"]),
    ...optional("minutes", numberOr(row["minutes"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
  };
}

function outlineOf(value: unknown): CourseOutline {
  const fn = "course_outline";
  const row = recordOf(value, fn);

  return {
    ...courseOf(row, fn),
    modules: recordsOf(row["modules"] ?? [], fn).map((item) => ({
      id: textOf(item["id"]),
      title: textOf(item["title"]),
      rank: textOf(item["rank"]),
      lessons: recordsOf(item["lessons"] ?? [], fn).map((lesson) =>
        outlineLessonOf(lesson, fn),
      ),
    })),
    ...optional(
      "progress",
      isRecord(row["progress"]) ? learnerOf(row["progress"], fn) : undefined,
    ),
  };
}

function quizOf(value: unknown): CourseQuiz | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const definition = value["definition"];

  // SAFETY: the forms block stores the JSON Schema it generated, a JSON object.
  const schema = isRecord(value["schema"])
    ? (value["schema"] as FormJsonSchema)
    : undefined;

  return {
    formId: textOf(value["formId"]),
    title: textOf(value["title"]),
    status: textOf(value["status"]),
    ...optional("versionId", optionalText(value["versionId"])),
    ...optional(
      "definition",
      isFormDefinition(definition) ? definition : undefined,
    ),
    ...optional("schema", schema),
  };
}

function lessonViewOf(value: unknown): CourseLessonView {
  const fn = "course_lesson";
  const row = recordOf(value, fn);

  return {
    ...lessonOf(row, fn),
    ...optional("quiz", quizOf(row["quiz"])),
    ...optional(
      "progress",
      isRecord(row["progress"]) ? entryOf(row["progress"], fn) : undefined,
    ),
  };
}

function checkOf(value: unknown): CourseCertificateCheck | null {
  if (!isRecord(value)) {
    return null;
  }

  return {
    id: textOf(value["id"]),
    courseId: textOf(value["courseId"]),
    courseTitle: textOf(value["courseTitle"]),
    organizationId: textOf(value["organizationId"]),
    issuedAt: requiredInstant(value["issuedAt"], "issuedAt"),
    expired: value["expired"] === true,
    valid: value["valid"] === true,
    ...optional("expiresAt", optionalInstant(value["expiresAt"])),
    ...optional("revokedAt", optionalInstant(value["revokedAt"])),
  };
}

function definedOf(input: object): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(input)) {
    if (value !== undefined) {
      out[key] = value;
    }
  }

  return out;
}

/**
 * The courses block: courses of modules and lessons, quizzes graded by forms,
 * per-lesson progress, completion and certificates, on enrollments.
 */
export function createCourses<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: CoursesOptions<S>): Courses<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "course fields");
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const learner =
    (fn: string) =>
    (value: unknown): CourseLearner =>
      learnerOf(value, fn);

  const client: Courses<F> = {
    upsert: (course) => {
      const { fields: extra, ...rest } = course;

      return tenant().andThen((organizationId) =>
        fields
          .args(extra)
          .andThen((checked) =>
            call(
              "save_course",
              {
                tenant: organizationId,
                course: {
                  ...definedOf(rest),
                  ...(checked === undefined ? {} : { fields: checked }),
                },
              },
              (value) => courseOf(value, "save_course"),
            ).andThen(fields.row),
          ),
      );
    },
    list: (filter = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_courses",
          { tenant: organizationId, status: filter.status ?? null },
          (value) =>
            recordsOf(value, "list_courses").map((row) =>
              courseOf(row, "list_courses"),
            ),
        ).andThen(fields.rows),
      ),
    delete: (courseId) =>
      call("delete_course", { course_id: courseId }, (value) => value === true),
    outline: (courseId) =>
      call("course_outline", { course_id: courseId }, outlineOf).andThen(
        fields.row,
      ),
    saveModule: ({ courseId, module }) =>
      call(
        "save_course_module",
        { course_id: courseId, module: definedOf(module) },
        (value) => moduleOf(value, "save_course_module"),
      ),
    deleteModule: (moduleId) =>
      call(
        "delete_course_module",
        { module_id: moduleId },
        (value) => value === true,
      ),
    saveLesson: ({ courseId, lesson }) =>
      call(
        "save_course_lesson",
        { course_id: courseId, lesson: definedOf(lesson) },
        (value) => lessonOf(value, "save_course_lesson"),
      ),
    deleteLesson: (lessonId) =>
      call(
        "delete_course_lesson",
        { lesson_id: lessonId },
        (value) => value === true,
      ),
    lesson: (lessonId) =>
      call("course_lesson", { lesson_id: lessonId }, lessonViewOf),
    enroll: ({ courseId, userId }) =>
      call(
        "enroll_in_course",
        { course_id: courseId, user_id: userId ?? null },
        learner("enroll_in_course"),
      ),
    unenroll: ({ courseId, userId }) =>
      call(
        "unenroll_from_course",
        { course_id: courseId, user_id: userId ?? null },
        learner("unenroll_from_course"),
      ),
    start: (lessonId) =>
      call("start_course_lesson", { lesson_id: lessonId }, (value) =>
        entryOf(value, "start_course_lesson"),
      ),
    complete: (lessonId) =>
      call(
        "complete_course_lesson",
        { lesson_id: lessonId, done: true },
        learner("complete_course_lesson"),
      ),
    reset: (lessonId) =>
      call(
        "complete_course_lesson",
        { lesson_id: lessonId, done: false },
        learner("complete_course_lesson"),
      ),
    submitQuiz: ({ lessonId, answers }) =>
      call("submit_course_quiz", { lesson_id: lessonId, answers }, (value) => {
        const row = recordOf(value, "submit_course_quiz");

        return {
          submission: recordOf(row["submission"], "submit_course_quiz"),
          passed: row["passed"] === true,
          progress: learnerOf(row["progress"], "submit_course_quiz"),
        };
      }),
    progress: ({ courseId, userId }) =>
      call(
        "course_progress",
        { course_id: courseId, user_id: userId ?? null },
        (value) =>
          isRecord(value) ? learnerOf(value, "course_progress") : null,
      ),
    learners: ({ courseId, filter = {} }) =>
      call(
        "list_course_learners",
        {
          course_id: courseId,
          status: filter.status ?? null,
          page_size: filter.pageSize ?? null,
          before: instantArg(filter.before) ?? null,
        },
        (value) =>
          recordsOf(value, "list_course_learners").map((row) =>
            learnerOf(row, "list_course_learners"),
          ),
      ),
    verifyCertificate: (code) =>
      call("verify_course_certificate", { code }, checkOf),
    revokeCertificate: (certificateId) =>
      call(
        "revoke_course_certificate",
        { certificate_id: certificateId },
        (value) => value === true,
      ),
    createFromOutline: ({ course, modules }) =>
      AsyncResult.from(async () => {
        const saved = await hooked.upsert(course);

        if (!saved.ok) {
          return saved;
        }

        for (const { title, lessons = [] } of modules) {
          const module = await hooked.saveModule({
            courseId: saved.data.id,
            module: { title },
          });

          if (!module.ok) {
            return module;
          }

          for (const lesson of lessons) {
            const lessonSaved = await hooked.saveLesson({
              courseId: saved.data.id,
              lesson: { ...lesson, moduleId: module.data.id },
            });

            if (!lessonSaved.ok) {
              return lessonSaved;
            }
          }
        }

        return hooked.outline(saved.data.id);
      }),
    publish: (courseId) => hooked.upsert({ id: courseId, status: "published" }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Courses<F> = withBlockHooks(client, options.hooks, {
    block: "courses",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
