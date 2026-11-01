import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { FormDefinition } from "../../src/core/contracts/form-definition.ts";

import { createCourses, sqlTransport } from "../../src/blocks/courses/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "custom-fields",
  "share-links",
  "rate-limit",
  "forms",
  "enrollments",
  "courses",
];

const QUIZ: FormDefinition = {
  scoring: { passMark: 50 },
  steps: [
    {
      key: "quiz",
      fields: [
        { key: "capital", label: "Capital", type: "text", correct: "Paris" },
        { key: "planet", label: "Planet", type: "text", correct: "Mars" },
      ],
    },
  ],
};

describe.skipIf(!live)("courses", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("orders lessons, grades quizzes, completes the course and issues a certificate", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });

      await s.asRole(owner);

      const courses = createCourses({ transport: sqlTransport(s.sql), tenant });

      const course = await courses
        .upsert({
          key: "onboarding",
          title: "Onboarding",
          certificate: true,
          validForMonths: 12,
        })
        .orThrow();

      expect(course).toMatchObject({
        status: "draft",
        certificate: true,
        validForMonths: 12,
      });
      expect(
        await s.hint("better_supabase.save_course($1, $2)", [
          tenant,
          { key: "onboarding", title: "Again" },
        ]),
      ).toBe("COURSE_EXISTS");

      const second = await courses
        .saveModule({ courseId: course.id, module: { title: "Second" } })
        .orThrow();

      const first = await courses
        .saveModule({
          courseId: course.id,
          module: { title: "First", rank: "U" },
        })
        .orThrow();

      expect(second.rank > first.rank).toBe(true);
      expect(
        await s.hint("better_supabase.save_course_module($1, $2)", [
          course.id,
          { title: "Bad", rank: "not a rank" },
        ]),
      ).toBe("COURSE_INVALID");

      const form = await s.value<{ id: string }>(
        "better_supabase.create_form($1, 'quiz', 'Quiz')",
        [tenant],
      );

      await s.value("better_supabase.publish_form_version($1, $2)", [
        form.id,
        QUIZ,
      ]);
      await s.value("better_supabase.update_form($1, null, null, 'open')", [
        form.id,
      ]);

      const intro = await courses
        .saveLesson({
          courseId: course.id,
          lesson: {
            moduleId: first.id,
            title: "Welcome",
            kind: "content",
            body: { text: "Hello" },
          },
        })
        .orThrow();

      const extra = await courses
        .saveLesson({
          courseId: course.id,
          lesson: {
            moduleId: first.id,
            title: "Further reading",
            required: false,
          },
        })
        .orThrow();

      const quiz = await courses
        .saveLesson({
          courseId: course.id,
          lesson: {
            moduleId: second.id,
            title: "Check",
            kind: "quiz",
            formId: form.id,
          },
        })
        .orThrow();

      expect(intro.rank < extra.rank).toBe(true);
      expect(
        await s.hint("better_supabase.save_course_lesson($1, $2)", [
          course.id,
          { moduleId: first.id, title: "No form", kind: "quiz" },
        ]),
      ).toBe("COURSE_INVALID");

      const outline = await courses.outline(course.id).orThrow();

      expect(outline.modules.map((module) => module.title)).toEqual([
        "First",
        "Second",
      ]);
      expect(outline.modules[0]!.lessons.map((lesson) => lesson.id)).toEqual([
        intro.id,
        extra.id,
      ]);

      await s.asRole(member);

      const learner = createCourses({ transport: sqlTransport(s.sql), tenant });

      expect(await learner.list().orThrow()).toEqual([]);
      expect(
        await s.hint("better_supabase.enroll_in_course($1)", [course.id]),
      ).toBe("COURSE_NOT_FOUND");

      await s.asRole(owner);
      expect(
        await s.hint("better_supabase.enroll_in_course($1, $2)", [
          course.id,
          member.id,
        ]),
      ).toBe("COURSE_NOT_PUBLISHED");
      await courses.upsert({ id: course.id, status: "published" }).orThrow();

      await s.asRole(member);
      expect(
        (await learner.list().orThrow()).map((listed) => listed.id),
      ).toEqual([course.id]);
      expect(
        await s.hint("better_supabase.course_lesson($1)", [intro.id]),
      ).toBe("COURSE_NOT_ENROLLED");

      const enrolled = await learner.enroll({ courseId: course.id }).orThrow();

      expect(enrolled).toMatchObject({
        status: "active",
        userId: member.id,
        completedLessons: 0,
        totalLessons: 2,
      });

      const view = await learner.lesson(quiz.id).orThrow();

      expect(view.quiz?.formId).toBe(form.id);
      expect(JSON.stringify(view.quiz)).not.toContain("Paris");

      expect(
        (await learner.start(intro.id).orThrow()).completedAt,
      ).toBeUndefined();
      expect(
        (await learner.complete(intro.id).orThrow()).completedLessons,
      ).toBe(1);
      expect(
        await s.hint("better_supabase.complete_course_lesson($1)", [quiz.id]),
      ).toBe("COURSE_INVALID");
      expect(
        await s.hint("better_supabase.complete_enrollment_step($1, $2)", [
          enrolled.enrollmentId,
          quiz.id,
        ]),
      ).toBe("ENROLLMENTS_INVALID");

      const failed = await learner
        .submitQuiz({
          lessonId: quiz.id,
          answers: { capital: "Lyon", planet: "Venus" },
        })
        .orThrow();

      expect(failed.passed).toBe(false);
      expect(failed.progress.status).toBe("active");

      const passed = await learner
        .submitQuiz({
          lessonId: quiz.id,
          answers: { capital: "Paris", planet: "Venus" },
        })
        .orThrow();

      expect(passed.passed).toBe(true);
      expect(passed.progress).toMatchObject({
        status: "completed",
        completedLessons: 2,
      });
      expect(
        passed.progress.lessons.find((entry) => entry.lessonId === quiz.id),
      ).toMatchObject({ attempts: 2, score: 1, maxScore: 2, passed: true });

      const certificate = passed.progress.certificate!;

      expect(certificate.code).toMatch(/^[0-9a-f]{32}$/);

      await s.asRole("anon");

      const anon = createCourses({ transport: sqlTransport(s.sql), tenant });

      const check = await anon.verifyCertificate(certificate.code).orThrow();

      expect(check).toMatchObject({
        courseTitle: "Onboarding",
        valid: true,
        expired: false,
      });
      expect(
        Temporal.Instant.compare(
          check!.expiresAt!,
          certificate.issuedAt.add({ hours: 24 * 330 }),
        ),
      ).toBe(1);
      expect(await anon.verifyCertificate("0".repeat(32)).orThrow()).toBeNull();

      await s.asRole(outsider);
      expect(
        await s.hint("better_supabase.course_outline($1)", [course.id]),
      ).toBe("COURSE_NOT_FOUND");
      expect(
        await s.hint("better_supabase.enroll_in_course($1)", [course.id]),
      ).toBe("COURSE_NOT_FOUND");

      await s.asRole(member);
      expect(
        await s.hint("better_supabase.save_course($1, $2)", [
          tenant,
          { key: "mine", title: "Mine" },
        ]),
      ).toBe("COURSE_FORBIDDEN");
      expect(
        await s.hint("better_supabase.list_course_learners($1)", [course.id]),
      ).toBe("COURSE_FORBIDDEN");

      await s.asRole(owner);

      const learners = await courses
        .learners({ courseId: course.id })
        .orThrow();

      expect(learners.map((row) => row.userId)).toEqual([member.id]);

      const added = await courses
        .saveLesson({
          courseId: course.id,
          lesson: { moduleId: second.id, title: "New material" },
        })
        .orThrow();

      expect(
        await courses
          .progress({ courseId: course.id, userId: member.id })
          .orThrow(),
      ).toMatchObject({ status: "active", totalLessons: 3 });

      await s.asRole(member);
      expect((await learner.complete(added.id).orThrow()).status).toBe(
        "completed",
      );
      expect(
        (await learner.progress({ courseId: course.id }).orThrow())?.certificate
          ?.code,
      ).toBe(certificate.code);

      await s.asRole(owner);
      expect(await courses.revokeCertificate(certificate.id).orThrow()).toBe(
        true,
      );
      expect(
        (await courses.verifyCertificate(certificate.code).orThrow())?.valid,
      ).toBe(false);

      await s.asRole(member);

      expect(
        await s.hint("better_supabase.unenroll_from_course($1)", [course.id]),
      ).toBe("COURSE_INVALID");

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          `select distinct type from better_supabase.outbox_events
           where type like 'course%' order by type`,
        ),
      ).toEqual(
        expect.arrayContaining([
          { type: "course.created" },
          { type: "course.enrolled" },
          { type: "course_lesson.completed" },
          { type: "course.completed" },
          { type: "course_certificate.issued" },
        ]),
      );

      expect(
        await s.rows<{ type: string }>(
          `select distinct event_type as type from better_supabase.audit_events
           where organization_id = $1 and event_type like 'course%' order by 1`,
          [tenant],
        ),
      ).toEqual(
        expect.arrayContaining([
          { type: "course.created" },
          { type: "course.enrolled" },
          { type: "course_certificate.revoked" },
        ]),
      );

      await s.asRole(owner);
      expect(await courses.delete(course.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("runs without forms, where quiz lessons are refused", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "audit", "enrollments", "courses"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      await s.asRole(owner);

      const courses = createCourses({ transport: sqlTransport(s.sql), tenant });

      const course = await courses
        .upsert({
          key: "basics",
          title: "Basics",
          status: "published",
          certificate: false,
        })
        .orThrow();

      const module = await courses
        .saveModule({ courseId: course.id, module: { title: "Only" } })
        .orThrow();

      expect(
        await s.hint("better_supabase.save_course_lesson($1, $2)", [
          course.id,
          {
            moduleId: module.id,
            title: "Quiz",
            kind: "quiz",
            formId: crypto.randomUUID(),
          },
        ]),
      ).toBe("COURSE_QUIZ_UNAVAILABLE");

      const lesson = await courses
        .saveLesson({
          courseId: course.id,
          lesson: { moduleId: module.id, title: "Read" },
        })
        .orThrow();

      await courses.enroll({ courseId: course.id }).orThrow();
      expect(
        (await courses.unenroll({ courseId: course.id }).orThrow()).status,
      ).toBe("cancelled");
      expect(
        (await courses.enroll({ courseId: course.id }).orThrow()).status,
      ).toBe("active");

      const done = await courses.complete(lesson.id).orThrow();

      expect(done.status).toBe("completed");
      expect(done.certificate).toBeUndefined();
      expect((await courses.reset(lesson.id).orThrow()).completedLessons).toBe(
        0,
      );
    } finally {
      await s.close();
    }
  });
});
