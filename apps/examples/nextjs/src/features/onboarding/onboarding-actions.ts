"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Creates the program new hires start with: four steps with due dates. */
export const setUpOnboardingProgram = bsb.blockAction(
  ({ db }) => db.enrollments,
  "saveProgram",
  {
    input: v.object({}),
    requireTenant: true,
    permission: "enrollments.manage",
    tags: () => [tags.onboarding()],
    refresh: true,
    args: (_) => [
      {
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
      },
    ],
  },
  (saved) => ({ key: saved.key }),
);

/** Starts an employee on a program. */
export const enrollEmployee = bsb.blockAction(
  ({ db }) => db.enrollments,
  "enroll",
  {
    input: v.object({
      program: v.pipe(v.string(), v.minLength(1)),
      employeeId: Id,
    }),
    requireTenant: true,
    permission: "enrollments.enroll",
    tags: () => [tags.onboarding()],
    refresh: true,
    args: ({ program, employeeId }) => [
      { program, subject: { type: "employee", id: employeeId } },
    ],
  },
  (enrolled) => ({ id: enrolled.id }),
);

/** Marks one step of an employee's onboarding done. */
export const completeOnboardingStep = bsb.blockAction(
  ({ db }) => db.enrollments,
  "complete",
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
  (done) => ({ id: done.id }),
);
