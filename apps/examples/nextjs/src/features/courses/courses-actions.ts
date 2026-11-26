"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Creates and publishes a one-module course to try the learner flow with. */
export const createSampleCourse = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      lessons: v.pipe(
        v.array(
          v.object({
            title: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
            text: v.pipe(v.string(), v.maxLength(4000)),
          }),
        ),
        v.minLength(1),
        v.maxLength(10),
      ),
    }),
    requireTenant: true,
    permission: "courses.manage",
    tags: () => [tags.courses()],
    refresh: true,
  },
  async ({ title, lessons }, { db }) => {
    const { courses } = db;

    const course = await courses.upsert({
      key: `sample-${crypto.randomUUID().slice(0, 8)}`,
      title,
    });

    if (!course.ok) {
      return course;
    }

    const outlineModule = await courses.saveModule({
      courseId: course.data.id,
      module: { title },
    });

    if (!outlineModule.ok) {
      return outlineModule;
    }

    for (const { title: lessonTitle, text } of lessons) {
      const lesson = await courses.saveLesson({
        courseId: course.data.id,
        lesson: {
          moduleId: outlineModule.data.id,
          title: lessonTitle,
          body: { text },
        },
      });

      if (!lesson.ok) {
        return lesson;
      }
    }

    const published = await courses.upsert({
      id: course.data.id,
      status: "published",
    });

    if (!published.ok) {
      return published;
    }

    return ok({ id: course.data.id });
  },
);

/** Enrolls the caller in a published course. */
export const enrollInCourse = bsb.blockAction(
  ({ db }) => db.courses,
  "enroll",
  {
    input: v.object({ courseId: Id }),
    requireTenant: true,
    permission: "courses.read",
    tags: () => [tags.courses()],
    refresh: true,
  },
  (learner) => ({ status: learner.status }),
);

/** Marks a content or video lesson done for the caller. */
export const completeLesson = bsb.blockAction(
  ({ db }) => db.courses,
  "complete",
  {
    input: v.object({ lessonId: Id }),
    requireTenant: true,
    permission: "courses.read",
    tags: () => [tags.courses()],
    refresh: true,
    args: ({ lessonId }) => [lessonId],
  },
  (learner) => ({ status: learner.status }),
);

const Answer = v.union([
  v.string(),
  v.number(),
  v.boolean(),
  v.array(v.string()),
]);

/** Submits a quiz; the database grades it, so the client can't set a score. */
export const submitQuiz = bsb.action(
  {
    input: v.object({
      lessonId: Id,
      answers: v.record(v.pipe(v.string(), v.maxLength(63)), Answer),
    }),
    requireTenant: true,
    permission: "courses.read",
    tags: () => [tags.courses()],
    refresh: true,
  },
  async ({ lessonId, answers }, { db }) => {
    const result = await db.courses.submitQuiz({ lessonId, answers });

    if (!result.ok) {
      return result;
    }

    const entry = result.data.progress.lessons.find(
      (lesson) => lesson.lessonId === lessonId,
    );

    return ok({
      passed: result.data.passed,
      score: entry?.score ?? null,
      max: entry?.maxScore ?? null,
    });
  },
);
