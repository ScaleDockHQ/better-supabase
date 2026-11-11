import "server-only";
import type { EnrollmentProgram } from "better-supabase/blocks/enrollments";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type { Loaded } from "@/features/people/people-queries";

import { readDirectory, settle } from "@/features/people/people-queries";
import { bsb } from "@/lib/supabase/server";

import type { OnboardingRow } from "./onboarding-list";

import { ONBOARDING_TAG } from "./onboarding-cache";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** The subject type the employees block registers its rows under. */
const EMPLOYEE = "employee";

/**
 * The runs of the organization's onboarding programs, with the employee's name.
 * The block lists a bounded window and has no search, so the list kit searches,
 * filters and pages these rows on the server (EX-901).
 */
export async function readOnboardingRows(
  db: Db,
  tenant: string,
): Promise<{
  readonly rows: readonly OnboardingRow[];
  readonly programs: readonly EnrollmentProgram[];
}> {
  const [programs, enrollments, directory] = await Promise.all([
    db.enrollments.programs().orThrow(),
    db.enrollments.list({ pageSize: 200 }).orThrow(),
    readDirectory(db, tenant),
  ]);

  const programName = new Map(programs.map((p) => [p.key, p.name]));
  const names = new Map(directory.map((e) => [e.id, e.name]));

  return {
    programs,
    rows: enrollments
      .filter((enrollment) => enrollment.subject.type === EMPLOYEE)
      .map((enrollment): OnboardingRow => ({
        id: enrollment.id,
        who: names.get(enrollment.subject.id) ?? "–",
        employeeId: enrollment.subject.id,
        program: enrollment.program,
        programName: programName.get(enrollment.program) ?? enrollment.program,
        status: enrollment.status,
        completed: enrollment.completedSteps,
        total: enrollment.totalSteps,
        startsAt: enrollment.startsAt?.toString() ?? null,
        enrolledAt: enrollment.enrolledAt.toString(),
      })),
  };
}

export interface OnboardingOverviewData {
  readonly programs: readonly { readonly key: string; readonly name: string }[];
  readonly employees: readonly {
    readonly value: string;
    readonly label: string;
  }[];
  readonly rows: readonly OnboardingRow[];
}

async function loadOnboarding(): Promise<OnboardingOverviewData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(ONBOARDING_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [{ rows, programs }, directory] = await Promise.all([
    readOnboardingRows(db, tenant),
    readDirectory(db, tenant),
  ]);

  return {
    rows,
    programs: programs
      .filter((program) => program.enabled)
      .map(({ key, name }) => ({ key, name })),
    employees: directory.map((e) => ({ value: e.id, label: e.name })),
  };
}

export function getOnboarding(): Promise<Loaded<OnboardingOverviewData>> {
  return settle(loadOnboarding);
}
