import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { LEAVE_TAG } from "@/features/leave/leave-cache";
import { ONBOARDING_TAG } from "@/features/onboarding/onboarding-cache";
import { bsb } from "@/lib/supabase/server";

import { PEOPLE_TAG } from "../people-cache";

export interface OnboardingStepRow {
  readonly id: string;
  readonly title: string;
  readonly done: boolean;
}

export interface OnboardingRun {
  readonly id: string;
  readonly programName: string;
  readonly status: string;
  readonly steps: readonly OnboardingStepRow[];
}

export interface LeaveBalanceRow {
  readonly key: string;
  readonly name: string;
  readonly unit: string;
  readonly granted: number;
  readonly taken: number;
  readonly pending: number;
  readonly available: number;
}

export interface EmployeeDesk {
  readonly runs: readonly OnboardingRun[];
  readonly balances: readonly LeaveBalanceRow[];
  readonly programs: readonly {
    readonly value: string;
    readonly label: string;
  }[];
}

/**
 * What the employee page adds to the directory row: the onboarding runs with
 * their steps, the leave balances and the programs a new hire can start on. A
 * run or balance the caller cannot read is left out.
 */
export async function loadEmployeeDesk(
  id: string,
): Promise<EmployeeDesk | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, ONBOARDING_TAG, LEAVE_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [programs, runs, balances] = await Promise.all([
    db.enrollments.programs(),
    db.enrollments.enrollmentPage({
      filters: { subjectType: ["employee"], subjectId: [id] },
      limit: 50,
    }),
    db.leave.balances({ organizationId: tenant, employeeId: id }),
  ]);

  const programList = programs.ok ? programs.data : [];

  const stepTitles = new Map(
    programList.flatMap((program) =>
      program.steps.map(
        (step) => [`${program.key}:${step.id}`, step.title ?? step.id] as const,
      ),
    ),
  );

  return {
    programs: programList
      .filter((program) => program.enabled)
      .map((program) => ({ value: program.key, label: program.name })),
    runs: runs.ok
      ? runs.data.items.map((run) => ({
          id: run.id,
          programName:
            programList.find((program) => program.key === run.program)?.name ??
            run.program,
          status: run.status,
          steps: run.steps.map((step) => ({
            id: step,
            title: stepTitles.get(`${run.program}:${step}`) ?? step,
            done: run.progress.some((entry) => entry.step === step),
          })),
        }))
      : [],
    balances: balances.ok
      ? balances.data.map((balance) => ({
          key: balance.key,
          name: balance.name,
          unit: balance.unit,
          granted: balance.granted,
          taken: balance.taken,
          pending: balance.pending,
          available: balance.available,
        }))
      : [],
  };
}

/** The enabled onboarding programs, for the dialog that onboards a new hire. */
export async function loadOnboardingPrograms(): Promise<
  readonly { readonly value: string; readonly label: string }[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(ONBOARDING_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const programs = await db.enrollments.programs().orThrow();

  return programs
    .filter((program) => program.enabled)
    .map((program) => ({ value: program.key, label: program.name }));
}
