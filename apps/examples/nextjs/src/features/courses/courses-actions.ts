"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
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
    authorize: (session) => can(session, "courses.manage"),
  },
  async ({ title, lessons }, { supabase, tenant, auth }) => {
    const { courses } = blocks(supabase, tenant);

    const course = await courses.save({
      key: `sample-${crypto.randomUUID().slice(0, 8)}`,
      title,
    });

    if (!course.ok) {
      return course;
    }

    const outlineModule = await courses.saveModule(course.data.id, { title });

    if (!outlineModule.ok) {
      return outlineModule;
    }

    for (const { title: lessonTitle, text } of lessons) {
      const lesson = await courses.saveLesson(course.data.id, {
        moduleId: outlineModule.data.id,
        title: lessonTitle,
        body: { text },
      });

      if (!lesson.ok) {
        return lesson;
      }
    }

    const published = await courses.save({
      id: course.data.id,
      status: "published",
    });

    if (!published.ok) {
      return published;
    }

    refreshCaller(auth);

    return ok({ id: course.data.id });
  },
);

/** Enrolls the caller in a published course. */
export const enrollInCourse = bsb.action(
  {
    input: v.object({ courseId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "courses.read"),
  },
  async ({ courseId }, { supabase, auth }) => {
    const learner = await blocks(supabase).courses.enroll(courseId);

    if (!learner.ok) {
      return learner;
    }

    refreshCaller(auth);

    return ok({ status: learner.data.status });
  },
);

/** Marks a content or video lesson done for the caller. */
export const completeLesson = bsb.action(
  {
    input: v.object({ lessonId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "courses.read"),
  },
  async ({ lessonId }, { supabase, auth }) => {
    const learner = await blocks(supabase).courses.complete(lessonId);

    if (!learner.ok) {
      return learner;
    }

    refreshCaller(auth);

    return ok({ status: learner.data.status });
  },
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
    authorize: (session) => can(session, "courses.read"),
  },
  async ({ lessonId, answers }, { supabase, auth }) => {
    const result = await blocks(supabase).courses.submitQuiz(lessonId, answers);

    if (!result.ok) {
      return result;
    }

    refreshCaller(auth);

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
