import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  courseInputSchema,
  courseLearnersBinding,
  courseLessonInputSchema,
  coursesBlock,
  coursesEvents,
  createCourses,
} from "../../../src/blocks/courses/index.ts";

const AT = "2026-10-22T10:00:00Z";

const COURSE = {
  id: "c1",
  organizationId: "org-1",
  key: "security-basics",
  title: "Security basics",
  summary: null,
  status: "published",
  certificate: true,
  validForMonths: 12,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  fields: { level: "intro" },
};

const LESSON = {
  id: "l1",
  courseId: "c1",
  moduleId: "m1",
  title: "Why it matters",
  kind: "content",
  body: { text: "Hello" },
  mediaUrl: null,
  formId: null,
  required: true,
  minutes: "5",
  rank: "a0",
  createdAt: AT,
  updatedAt: AT,
};

const LEARNER = {
  enrollmentId: "e1",
  courseId: "c1",
  organizationId: "org-1",
  userId: "u2",
  status: "completed",
  completedLessons: 2,
  totalLessons: 2,
  lessons: [
    {
      lessonId: "l1",
      startedAt: AT,
      completedAt: AT,
      attempts: 0,
      submissionId: null,
      score: null,
      maxScore: null,
      passed: null,
    },
    {
      lessonId: "l2",
      startedAt: AT,
      completedAt: AT,
      attempts: 2,
      submissionId: "s1",
      score: 1,
      maxScore: "2",
      passed: true,
    },
  ],
  certificate: {
    id: "cert1",
    courseId: "c1",
    userId: "u2",
    code: "a".repeat(32),
    issuedAt: AT,
    revokedAt: null,
    expiresAt: "2027-10-22T10:00:00Z",
  },
  enrolledAt: AT,
  completedAt: AT,
  cancelledAt: null,
  updatedAt: AT,
};

const DEFINITION = {
  steps: [
    {
      key: "main",
      fields: [{ key: "capital", label: "Capital", type: "text" }],
    },
  ],
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createCourses", () => {
  it("saves, lists and deletes courses with their fields", async () => {
    const fake = fakeTransport({
      save_course: COURSE,
      list_courses: [
        COURSE,
        { ...COURSE, id: "c2", summary: "Intro", createdBy: null },
      ],
      delete_course: true,
    });

    const courses = createCourses({
      transport: fake.transport,
      tenant: "org-1",
      fields: v.object({ level: v.string() }),
    });

    const saved = await courses
      .upsert({
        key: "security-basics",
        title: "Security basics",
        validForMonths: 12,
        fields: { level: "intro" },
      })
      .orThrow();

    expect(saved.createdAt).toBeInstanceOf(Temporal.Instant);
    expect(saved).toMatchObject({
      status: "published",
      certificate: true,
      validForMonths: 12,
      createdBy: "u1",
      fields: { level: "intro" },
    });
    expect(saved).not.toHaveProperty("summary");

    const list = await courses.list({ status: "published" }).orThrow();

    expect(list[1]).toMatchObject({ summary: "Intro" });
    expect(list[1]).not.toHaveProperty("createdBy");
    await courses.list().orThrow();
    expect(await courses.delete("c2").orThrow()).toBe(true);

    expect(fake.calls).toEqual([
      [
        "save_course",
        {
          tenant: "org-1",
          course: {
            key: "security-basics",
            title: "Security basics",
            validForMonths: 12,
            fields: { level: "intro" },
          },
        },
      ],
      ["list_courses", { tenant: "org-1", status: "published" }],
      ["list_courses", { tenant: "org-1", status: null }],
      ["delete_course", { course_id: "c2" }],
    ]);
  });

  it("saves a course without fields and with certificates off", async () => {
    const fake = fakeTransport({
      save_course: { ...COURSE, certificate: false, fields: null },
    });

    const courses = createCourses({
      transport: fake.transport,
      tenant: "org-1",
    });

    const saved = await courses
      .upsert({ id: "c1", certificate: false })
      .orThrow();

    expect(saved.certificate).toBe(false);
    expect(saved.fields).toEqual({});
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      course: { id: "c1", certificate: false },
    });
  });

  it("authors modules and lessons", async () => {
    const fake = fakeTransport({
      save_course_module: {
        id: "m1",
        courseId: "c1",
        title: "Introduction",
        rank: "a0",
        createdAt: AT,
        updatedAt: AT,
      },
      delete_course_module: false,
      save_course_lesson: LESSON,
      delete_course_lesson: true,
    });

    const courses = createCourses({ transport: fake.transport });

    const module = await courses
      .saveModule("c1", { title: "Introduction" })
      .orThrow();

    expect(module.rank).toBe("a0");
    expect(await courses.deleteModule("m1").orThrow()).toBe(false);

    const lesson = await courses
      .saveLesson("c1", { moduleId: "m1", title: "Why it matters" })
      .orThrow();

    expect(lesson).toMatchObject({
      kind: "content",
      body: { text: "Hello" },
      minutes: 5,
      required: true,
    });
    expect(lesson).not.toHaveProperty("mediaUrl");
    expect(lesson).not.toHaveProperty("formId");
    expect(await courses.deleteLesson("l1").orThrow()).toBe(true);

    expect(fake.calls).toEqual([
      [
        "save_course_module",
        { course_id: "c1", module: { title: "Introduction" } },
      ],
      ["delete_course_module", { module_id: "m1" }],
      [
        "save_course_lesson",
        {
          course_id: "c1",
          lesson: { moduleId: "m1", title: "Why it matters" },
        },
      ],
      ["delete_course_lesson", { lesson_id: "l1" }],
    ]);
  });

  it("reads an outline with and without progress", async () => {
    const outline = {
      ...COURSE,
      modules: [
        {
          id: "m1",
          title: "Introduction",
          rank: "a0",
          lessons: [
            {
              id: "l1",
              moduleId: "m1",
              title: "Why it matters",
              kind: "content",
              required: true,
              minutes: 5,
              rank: "a0",
              completedAt: AT,
            },
            {
              id: "l2",
              moduleId: "m1",
              title: "Quiz",
              kind: "quiz",
              required: false,
              minutes: null,
              rank: "a1",
              completedAt: null,
            },
          ],
        },
        { id: "m2", title: "Empty", rank: "a1", lessons: null },
      ],
      progress: LEARNER,
    };

    const fake = fakeTransport({ course_outline: outline });
    const courses = createCourses({ transport: fake.transport });
    const read = await courses.outline("c1").orThrow();

    expect(read.modules[0]?.lessons[0]?.completedAt).toBeInstanceOf(
      Temporal.Instant,
    );
    expect(read.modules[0]?.lessons[1]).toMatchObject({ required: false });
    expect(read.modules[0]?.lessons[1]).not.toHaveProperty("minutes");
    expect(read.modules[0]?.lessons[1]).not.toHaveProperty("completedAt");
    expect(read.modules[1]?.lessons).toEqual([]);
    expect(read.progress?.certificate?.code).toBe("a".repeat(32));
    expect(read.progress?.certificate?.expiresAt).toBeInstanceOf(
      Temporal.Instant,
    );
    expect(read.progress?.lessons[1]).toMatchObject({
      attempts: 2,
      score: 1,
      maxScore: 2,
      passed: true,
      submissionId: "s1",
    });
    expect(read.progress?.lessons[0]).not.toHaveProperty("score");

    const bare = createCourses({
      transport: fakeTransport({
        course_outline: { ...COURSE, modules: null, progress: null },
      }).transport,
    });

    const empty = await bare.outline("c1").orThrow();

    expect(empty.modules).toEqual([]);
    expect(empty).not.toHaveProperty("progress");
  });

  it("reads a lesson with its quiz", async () => {
    const fake = fakeTransport({
      course_lesson: {
        ...LESSON,
        kind: "quiz",
        body: null,
        formId: "f1",
        quiz: {
          formId: "f1",
          title: "Check yourself",
          status: "published",
          versionId: "v1",
          definition: DEFINITION,
          schema: { type: "object" },
        },
        progress: LEARNER.lessons[1],
      },
    });

    const courses = createCourses({ transport: fake.transport });
    const lesson = await courses.lesson("l1").orThrow();

    expect(lesson).not.toHaveProperty("body");
    expect(lesson.quiz).toEqual({
      formId: "f1",
      title: "Check yourself",
      status: "published",
      versionId: "v1",
      definition: DEFINITION,
      schema: { type: "object" },
    });
    expect(lesson.progress?.attempts).toBe(2);
    expect(fake.calls).toEqual([["course_lesson", { lesson_id: "l1" }]]);
  });

  it("drops a quiz definition or schema that isn't one", async () => {
    const courses = createCourses({
      transport: fakeTransport({
        course_lesson: {
          ...LESSON,
          quiz: {
            formId: "f1",
            title: "Draft quiz",
            status: "draft",
            versionId: null,
            definition: null,
            schema: "nope",
          },
          progress: null,
        },
      }).transport,
    });

    const lesson = await courses.lesson("l1").orThrow();

    expect(lesson.quiz).toEqual({
      formId: "f1",
      title: "Draft quiz",
      status: "draft",
    });
    expect(lesson).not.toHaveProperty("progress");

    const plain = createCourses({
      transport: fakeTransport({ course_lesson: { ...LESSON, quiz: null } })
        .transport,
    });

    expect(await plain.lesson("l1").orThrow()).not.toHaveProperty("quiz");
  });

  it("enrolls, progresses and grades a learner", async () => {
    const active = {
      ...LEARNER,
      status: "active",
      certificate: null,
      completedAt: null,
      lessons: null,
    };

    const fake = fakeTransport({
      enroll_in_course: active,
      unenroll_from_course: { ...active, status: "cancelled", cancelledAt: AT },
      start_course_lesson: { lessonId: "l1", startedAt: AT, attempts: null },
      complete_course_lesson: LEARNER,
      submit_course_quiz: {
        submission: { id: "s1" },
        passed: true,
        progress: LEARNER,
      },
      course_progress: null,
      list_course_learners: [LEARNER],
    });

    const courses = createCourses({ transport: fake.transport });

    const enrolled = await courses.enroll("c1").orThrow();

    expect(enrolled.lessons).toEqual([]);
    expect(enrolled).not.toHaveProperty("certificate");
    expect(
      (await courses.unenroll("c1", "u2").orThrow()).cancelledAt,
    ).toBeInstanceOf(Temporal.Instant);

    const started = await courses.start("l1").orThrow();

    expect(started.attempts).toBe(0);
    expect(started).not.toHaveProperty("completedAt");
    expect((await courses.complete("l1").orThrow()).status).toBe("completed");
    await courses.reset("l1").orThrow();

    const graded = await courses
      .submitQuiz("l2", { capital: "Paris" })
      .orThrow();

    expect(graded.passed).toBe(true);
    expect(graded.submission).toEqual({ id: "s1" });
    expect(await courses.progress("c1").orThrow()).toBeNull();

    const learners = await courses
      .learners("c1", {
        status: "completed",
        pageSize: 10,
        before: Temporal.Instant.from(AT),
      })
      .orThrow();

    expect(learners).toHaveLength(1);
    await courses.learners("c1").orThrow();

    expect(fake.calls).toEqual([
      ["enroll_in_course", { course_id: "c1", user_id: null }],
      ["unenroll_from_course", { course_id: "c1", user_id: "u2" }],
      ["start_course_lesson", { lesson_id: "l1" }],
      ["complete_course_lesson", { lesson_id: "l1", done: true }],
      ["complete_course_lesson", { lesson_id: "l1", done: false }],
      [
        "submit_course_quiz",
        { lesson_id: "l2", answers: { capital: "Paris" } },
      ],
      ["course_progress", { course_id: "c1", user_id: null }],
      [
        "list_course_learners",
        {
          course_id: "c1",
          status: "completed",
          page_size: 10,
          before: "2026-10-22T10:00:00Z",
        },
      ],
      [
        "list_course_learners",
        { course_id: "c1", status: null, page_size: null, before: null },
      ],
    ]);
  });

  it("reads another learner's progress", async () => {
    const fake = fakeTransport({ course_progress: LEARNER });
    const courses = createCourses({ transport: fake.transport });

    const progress = await courses.progress("c1", "u2").orThrow();

    expect(progress?.userId).toBe("u2");
    expect(fake.calls[0]).toEqual([
      "course_progress",
      { course_id: "c1", user_id: "u2" },
    ]);
  });

  it("verifies and revokes certificates", async () => {
    const fake = fakeTransport({
      verify_course_certificate: {
        id: "cert1",
        courseId: "c1",
        courseTitle: "Security basics",
        organizationId: "org-1",
        issuedAt: AT,
        revokedAt: AT,
        expiresAt: AT,
        expired: true,
        valid: false,
      },
      revoke_course_certificate: true,
    });

    const courses = createCourses({ transport: fake.transport });
    const check = await courses.verifyCertificate("a".repeat(32)).orThrow();

    expect(check).toMatchObject({
      valid: false,
      expired: true,
      courseTitle: "Security basics",
    });
    expect(check?.expiresAt).toBeInstanceOf(Temporal.Instant);
    expect(check?.revokedAt).toBeInstanceOf(Temporal.Instant);
    expect(await courses.revokeCertificate("cert1").orThrow()).toBe(true);

    const unknown = createCourses({
      transport: fakeTransport({ verify_course_certificate: null }).transport,
    });

    expect(
      await unknown.verifyCertificate("b".repeat(32)).orThrow(),
    ).toBeNull();
  });

  it("rejects an unknown status from the database", async () => {
    const courses = createCourses({
      transport: fakeTransport({
        enroll_in_course: { ...LEARNER, status: "paused" },
        save_course_lesson: { ...LESSON, kind: "podcast" },
      }).transport,
    });

    expect((await courses.enroll("c1")).ok).toBe(false);
    expect((await courses.saveLesson("c1", {})).ok).toBe(false);
  });

  it("fails tenant-scoped calls without a tenant", async () => {
    const fake = fakeTransport({});
    const courses = createCourses({ transport: fake.transport });

    expect((await courses.upsert({ title: "x" })).ok).toBe(false);
    expect((await courses.list()).ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });

  it("refuses fields that fail their schema", async () => {
    const fake = fakeTransport({});

    const courses = createCourses({
      transport: fake.transport,
      tenant: "org-1",
      fields: v.object({ level: v.picklist(["intro", "advanced"]) }),
    });

    // SAFETY: the test sends a value the schema refuses.
    const bad = { level: "expert" } as unknown as { level: "intro" };
    const saved = await courses.upsert({ title: "x", fields: bad });

    expect(saved.ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});

describe("courseLearnersBinding", () => {
  it("loads a course's learners and enrolls through its writes", async () => {
    const fake = fakeTransport({
      list_course_learners: [LEARNER],
      enroll_in_course: LEARNER,
      unenroll_from_course: LEARNER,
    });

    const courses = createCourses({ transport: fake.transport });
    const subject = { type: "course", id: "c1" };

    const learners = await courseLearnersBinding
      .load(courses, subject, undefined)
      .orThrow();

    expect(learners).toHaveLength(1);
    await courseLearnersBinding.writes.enroll
      .run(courses, subject, { userId: "u2" })
      .orThrow();
    await courseLearnersBinding.writes.unenroll
      .run(courses, subject, {})
      .orThrow();

    expect(fake.calls.slice(1)).toEqual([
      ["enroll_in_course", { course_id: "c1", user_id: "u2" }],
      ["unenroll_from_course", { course_id: "c1", user_id: null }],
    ]);
    expect(courseLearnersBinding.events).toContain("course.*");
  });

  it("isn't attached to other subjects' record pages", () => {
    expect(coursesBlock.record).toBeUndefined();
    expect(coursesBlock.recipes).toEqual(["course-outline", "lesson-player"]);
    expect(coursesEvents.types).toContain("course_certificate.issued");
  });
});

describe("course schemas", () => {
  it("checks a course and a lesson against the SQL bounds", async () => {
    const course = await courseInputSchema["~standard"].validate({
      key: "security-basics",
      title: "Security basics",
      status: "published",
    });

    expect(course.issues).toBeUndefined();

    const badCourse = await courseInputSchema["~standard"].validate({
      title: "",
      status: "live",
    });

    expect(badCourse.issues?.length).toBeGreaterThan(0);

    const lesson = await courseLessonInputSchema["~standard"].validate({
      title: "Quiz",
      kind: "quiz",
      formId: "00000000-0000-4000-8000-000000000001",
      minutes: 10,
    });

    expect(lesson.issues).toBeUndefined();

    const badLesson = await courseLessonInputSchema["~standard"].validate({
      kind: "podcast",
      minutes: 0,
    });

    expect(badLesson.issues?.length).toBeGreaterThan(0);
  });
});
