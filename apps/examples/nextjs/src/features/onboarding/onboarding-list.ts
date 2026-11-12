import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

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
  sorts: ["newest", "progress", "name"],
  defaultSort: "newest",
  pageSize: 25,
});

export const onboardingSpec: BlockListSpec<OnboardingRow> = {
  text: (row) => [row.who, row.programName],
  facets: { status: (row) => row.status, program: (row) => row.program },
  sorts: {
    newest: (a, b) => b.enrolledAt.localeCompare(a.enrolledAt),
    // The runs furthest from done first.
    progress: (a, b) =>
      a.completed / Math.max(a.total, 1) - b.completed / Math.max(b.total, 1),
    name: (a, b) => a.who.localeCompare(b.who),
  },
};
