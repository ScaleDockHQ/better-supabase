"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Creates the program new hires start with: four steps with due dates. */
export const setUpOnboardingProgram = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "enrollments.manage",
    tags: () => [tags.onboarding()],
    refresh: true,
  },
  async (_input, { db }) => {
    const saved = await db.enrollments.saveProgram({
      key: "new-hire",
      name: "New hire",
      description: "What a new employee finishes in the first weeks.",
      subjectTypes: ["employee"],
      steps: [
        {
          id: "equipment",
          title: "Hand over equipment",
          due: { days: 0, from: "start" },
        },
        {
          id: "accounts",
          title: "Create accounts",
          due: { days: 1, from: "start" },
        },
        {
          id: "intro",
          title: "Meet the team",
          due: { days: 7, from: "start" },
        },
        {
          id: "review",
          title: "First review",
          due: { days: 30, from: "start" },
        },
      ],
    });

    if (!saved.ok) {
      return saved;
    }

    return ok({ key: saved.data.key });
  },
);

/** Starts an employee on a program. */
export const enrollEmployee = bsb.action(
  {
    input: v.object({
      program: v.pipe(v.string(), v.minLength(1)),
      employeeId: Id,
    }),
    requireTenant: true,
    permission: "enrollments.enroll",
    tags: () => [tags.onboarding()],
    refresh: true,
  },
  async ({ program, employeeId }, { db }) => {
    const enrolled = await db.enrollments.enroll({
      program,
      subject: { type: "employee", id: employeeId },
    });

    if (!enrolled.ok) {
      return enrolled;
    }

    return ok({ id: enrolled.data.id });
  },
);

/** Marks one step of an employee's onboarding done. */
export const completeOnboardingStep = bsb.action(
  {
    input: v.object({
      enrollmentId: Id,
      step: v.pipe(v.string(), v.minLength(1)),
    }),
    requireTenant: true,
    permission: "enrollments.enroll",
    tags: () => [tags.onboarding(), tags.people()],
    refresh: true,
  },
  async ({ enrollmentId, step }, { db }) => {
    const done = await db.enrollments.complete({ enrollmentId, step });

    if (!done.ok) {
      return done;
    }

    return ok({ id: done.data.id });
  },
);
