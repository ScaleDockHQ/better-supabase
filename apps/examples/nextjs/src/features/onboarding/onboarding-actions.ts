"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { ONBOARDING_TAG } from "./onboarding-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Creates the program new hires start with: four steps with due dates. */
export const setUpOnboardingProgram = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "enrollments.manage",
  },
  async (_input, { db, auth }) => {
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

    await refreshCaller(auth, [ONBOARDING_TAG]);

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
  },
  async ({ program, employeeId }, { db, auth }) => {
    const enrolled = await db.enrollments.enroll({
      program,
      subject: { type: "employee", id: employeeId },
    });

    if (!enrolled.ok) {
      return enrolled;
    }

    await refreshCaller(auth, [ONBOARDING_TAG]);

    return ok({ id: enrolled.data.id });
  },
);
