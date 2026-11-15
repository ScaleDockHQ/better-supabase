import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

/** One employee's run of an onboarding program. */
export interface OnboardingRow {
  readonly id: string;
  readonly who: string;
  readonly employeeId: string;
  readonly program: string;
  readonly programName: string;
  readonly status: "active" | "completed" | "cancelled";
  readonly completed: number;
  readonly total: number;
  readonly startsAt: string | null;
  readonly enrolledAt: string;
}

export const onboardingList = defineBlockList({
  facets: ["status", "program"],
  sorts: ["newest", "updated"],
  defaultSort: "newest",
  pageSize: 25,
});

/** The onboarding list's URL names on the enrollments block's list. */
export const onboardingMap: EntityListMap = {
  sorts: {
    newest: { by: "enrolledAt", direction: "desc" },
    updated: { by: "updatedAt", direction: "desc" },
  },
  // Only employees' runs; other subjects enroll in programs of their own.
  defaultFilters: { subjectType: ["employee"] },
};
