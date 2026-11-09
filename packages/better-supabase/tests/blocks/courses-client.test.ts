import { describe, expect, it } from "vitest";

import { createCourses } from "../../src/blocks/courses/courses.ts";

const STAMP = "2026-11-01T00:00:00Z";

const course = {
  id: "c1",
  organizationId: "org-1",
  key: "welcome",
  title: "Welcome",
  status: "draft",
  certificate: true,
  createdAt: STAMP,
  updatedAt: STAMP,
};

const moduleRow = {
  id: "m1",
  courseId: "c1",
  title: "Start",
  rank: "a",
  createdAt: STAMP,
  updatedAt: STAMP,
};

const lesson = {
  id: "l1",
  courseId: "c1",
  moduleId: "m1",
  title: "Hello",
  kind: "content",
  required: true,
  rank: "a",
  createdAt: STAMP,
  updatedAt: STAMP,
};

const outline = {
  ...course,
  modules: [
    {
      id: "m1",
      title: "Start",
      rank: "a",
      lessons: [
        {
          id: "l1",
          moduleId: "m1",
          title: "Hello",
          kind: "content",
          required: true,
          rank: "a",
        },
      ],
    },
  ],
};

function transport(fail?: string) {
  const rows: Record<string, unknown> = {
    save_course: course,
    save_course_module: moduleRow,
    save_course_lesson: lesson,
    course_outline: outline,
    list_courses: [course, { ...course, id: "c2", key: "next" }],
  };

  return {
    call(_schema: string, fn: string, _args: Record<string, unknown>) {
      if (fn === fail) {
        return Promise.reject(new Error(fn));
      }

      return Promise.resolve(rows[fn]);
    },
  };
}

const input = {
  course: { title: "Welcome", key: "welcome" },
  modules: [
    { title: "Empty" },
    { title: "Start", lessons: [{ title: "Hello", kind: "content" as const }] },
  ],
};

describe("course client", () => {
  it("builds an outline and stops at the first failed step", async () => {
    const saved = await createCourses({
      transport: transport(),
      tenant: "org-1",
    }).createFromOutline(input);

    expect(saved.ok ? saved.data.id : saved.error.message).toBe("c1");

    for (const fn of [
      "save_course",
      "save_course_module",
      "save_course_lesson",
    ]) {
      const failed = await createCourses({
        transport: transport(fn),
        tenant: "org-1",
      }).createFromOutline(input);

      expect(failed.ok).toBe(false);
    }
  });

  it("limits a course list", async () => {
    const courses = createCourses({ transport: transport(), tenant: "org-1" });
    const listed = await courses.list({ limit: 1 });
    const all = await courses.list();

    expect(listed.ok ? listed.data : []).toHaveLength(1);
    expect(all.ok ? all.data : []).toHaveLength(2);
  });
});
