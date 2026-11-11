import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

/** One computed deadline of a record, as the page and the list route send it. */
export interface DeadlineRow {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly kind: string;
  readonly jurisdiction: string;
  readonly groupKey: string;
  readonly result: string;
  readonly dueOn: string | null;
  readonly provisional: boolean;
  readonly state: "pending" | "satisfied";
  readonly missing: number;
  readonly computedAt: string;
}

export const deadlineList = defineBlockList({
  facets: ["state", "result", "kind"],
  sorts: ["due", "newest", "kind"],
  defaultSort: "due",
  pageSize: 25,
});

export const deadlineSpec: BlockListSpec<DeadlineRow> = {
  text: (row) => [row.kind, row.groupKey, row.jurisdiction, row.subjectType],
  facets: {
    state: (row) => row.state,
    result: (row) => row.result,
    kind: (row) => row.kind,
  },
  sorts: {
    // The nearest date first; deadlines with no date last.
    due: (a, b) =>
      (a.dueOn ?? "9999-12-31").localeCompare(b.dueOn ?? "9999-12-31"),
    newest: (a, b) => b.computedAt.localeCompare(a.computedAt),
    kind: (a, b) => a.kind.localeCompare(b.kind),
  },
};
