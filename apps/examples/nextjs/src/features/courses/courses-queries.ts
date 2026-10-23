import "server-only";
import type {
  CourseLearner,
  CourseLearnerStatus,
  CourseLessonKind,
  CourseStatus,
} from "better-supabase/blocks/courses";
import type { FormField } from "better-supabase/blocks/forms";

import { tenantOf } from "better-supabase/next";
import { notFound, unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

export interface CourseCard {
  readonly id: string;
  readonly title: string;
  readonly summary: string | null;
  readonly status: CourseStatus;
}

export interface OutlineLesson {
  readonly id: string;
  readonly title: string;
  readonly kind: CourseLessonKind;
  readonly required: boolean;
  readonly minutes: number | null;
  readonly done: boolean;
}

export interface OutlineModule {
  readonly id: string;
  readonly title: string;
  readonly lessons: readonly OutlineLesson[];
}

export interface LearnerView {
  readonly status: CourseLearnerStatus;
  readonly completed: number;
  readonly total: number;
  readonly certificateCode: string | null;
}

export interface OutlineView {
  readonly id: string;
  readonly title: string;
  readonly summary: string | null;
  readonly status: CourseStatus;
  readonly modules: readonly OutlineModule[];
  /** `null` when the caller isn't enrolled. */
  readonly learner: LearnerView | null;
}

export interface LessonView {
  readonly id: string;
  readonly courseId: string;
  readonly title: string;
  readonly kind: CourseLessonKind;
  /** The text of a `{ text }` body, the shape this example saves. */
  readonly text: string | null;
  readonly mediaUrl: string | null;
  readonly done: boolean;
  /** A quiz lesson's fields, without the answer key. */
  readonly quiz: readonly FormField[] | null;
  readonly lastScore: { readonly score: number; readonly max: number } | null;
}

function learnerView(learner: CourseLearner | undefined): LearnerView | null {
  return learner === undefined
    ? null
    : {
        status: learner.status,
        completed: learner.completedLessons,
        total: learner.totalLessons,
        certificateCode:
          learner.certificate && !learner.certificate.revokedAt
            ? learner.certificate.code
            : null,
      };
}

/** The `{ text }` body this example saves; other shapes show no text. */
const TextBody = v.object({ text: v.string() });

/** A failed read throws, so it is never cached and Retry reads again. */
async function loadCourses(): Promise<readonly CourseCard[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const courses = await db.courses.list().orThrow();

  return courses.map((course) => ({
    id: course.id,
    title: course.title,
    summary: course.summary ?? null,
    status: course.status,
  }));
}

export async function getCourses(): Promise<Loaded<readonly CourseCard[]>> {
  try {
    const courses = await loadCourses();

    return courses === null
      ? { kind: "no-organization" }
      : { kind: "ok", data: courses };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

async function loadOutline(id: string): Promise<OutlineView | "not-found"> {
  "use cache: private";
  const { db } = await bsb.cached();
  const outline = await db.courses.outline(id);

  if (!outline.ok) {
    if (outline.error.kind === "not_found") {
      return "not-found";
    }

    throw new Error(outline.error.message);
  }

  const course = outline.data;

  return {
    id: course.id,
    title: course.title,
    summary: course.summary ?? null,
    status: course.status,
    modules: course.modules.map((module) => ({
      id: module.id,
      title: module.title,
      lessons: module.lessons.map((lesson) => ({
        id: lesson.id,
        title: lesson.title,
        kind: lesson.kind,
        required: lesson.required,
        minutes: lesson.minutes ?? null,
        done: lesson.completedAt !== undefined,
      })),
    })),
    learner: learnerView(course.progress),
  };
}

export async function getOutline(id: string): Promise<Loaded<OutlineView>> {
  if (!UUID.test(id)) {
    notFound();
  }

  let outline: OutlineView | "not-found";

  try {
    outline = await loadOutline(id);
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }

  if (outline === "not-found") {
    notFound();
  }

  return { kind: "ok", data: outline };
}

async function loadLesson(id: string): Promise<LessonView | "not-found"> {
  "use cache: private";
  const { db } = await bsb.cached();
  const lesson = await db.courses.lesson(id);

  if (!lesson.ok) {
    if (lesson.error.kind === "not_found") {
      return "not-found";
    }

    throw new Error(lesson.error.message);
  }

  const view = lesson.data;
  const progress = view.progress;

  return {
    id: view.id,
    courseId: view.courseId,
    title: view.title,
    kind: view.kind,
    text: v.is(TextBody, view.body) ? view.body.text : null,
    mediaUrl: view.mediaUrl ?? null,
    done: progress?.completedAt !== undefined,
    quiz: view.quiz?.definition?.steps.flatMap((step) => step.fields) ?? null,
    lastScore:
      progress?.score === undefined || progress.maxScore === undefined
        ? null
        : { score: progress.score, max: progress.maxScore },
  };
}

/** Not enrolled reads as not found: the outline offers Enroll. */
export async function getLesson(id: string): Promise<Loaded<LessonView>> {
  if (!UUID.test(id)) {
    notFound();
  }

  let lesson: LessonView | "not-found";

  try {
    lesson = await loadLesson(id);
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }

  if (lesson === "not-found") {
    notFound();
  }

  return { kind: "ok", data: lesson };
}
