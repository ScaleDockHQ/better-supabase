import "server-only";
import type { EnrollmentProgram } from "better-supabase/blocks/enrollments";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type {
  DirectoryEmployee,
  Loaded,
} from "@/features/people/people-queries";

import { getDirectory, settle } from "@/features/people/people-queries";
import { pageEntityRows } from "@/lib/block-entity-page";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import type { OnboardingRow } from "./onboarding-list";

import { onboardingList, onboardingMap } from "./onboarding-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * One page of the employees' onboarding runs for a list query, searched,
 * filtered and sorted by the enrollments block's `enrollmentPage` and counted
 * by `enrollmentFacets`, with each employee's name from the directory. The
 * programs and the directory load beside the page, in one wave.
 */
export async function getOnboardingPage(
  db: Db,
  tenant: string,
  query: RecordListUrlQuery,
): Promise<{
  readonly page: RecordListPage<OnboardingRow>;
  readonly programs: readonly EnrollmentProgram[];
  readonly directory: readonly DirectoryEmployee[];
}> {
  const { enrollments } = db;

  const context = Promise.all([
    enrollments.programs().orThrow(),
    getDirectory(db, tenant),
  ]).then(([programs, directory]) => ({ programs, directory }));

  const page = await pageEntityRows({
    pager: {
      page: (options) => enrollments.enrollmentPage(options),
      facets: (options) => enrollments.enrollmentFacets(options),
    },
    map: onboardingMap,
    query,
    pageSize: onboardingList.config.pageSize,
    rowsOf: async (items) => {
      const { programs, directory } = await context;
      const programName = new Map(programs.map((p) => [p.key, p.name]));
      const names = new Map(directory.map((e) => [e.id, e.name]));

      return items.map((enrollment): OnboardingRow => ({
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
      }));
    },
  });

  return { page, ...(await context) };
}

export interface OnboardingOverviewData {
  readonly programs: readonly { readonly key: string; readonly name: string }[];
  readonly employees: readonly {
    readonly value: string;
    readonly label: string;
  }[];
  readonly initial: RecordListPage<OnboardingRow>;
}

async function loadOnboarding(): Promise<OnboardingOverviewData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.onboarding());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { page, programs, directory } = await getOnboardingPage(
    db,
    tenant,
    onboardingList.defaults,
  );

  return {
    initial: page,
    programs: programs
      .filter((program) => program.enabled)
      .map(({ key, name }) => ({ key, name })),
    employees: directory.map((e) => ({ value: e.id, label: e.name })),
  };
}

export function getOnboarding(): Promise<Loaded<OnboardingOverviewData>> {
  return settle(loadOnboarding);
}
