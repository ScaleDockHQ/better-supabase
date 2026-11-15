import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

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
  facets: ["state", "result", "group"],
  sorts: ["due", "newest"],
  defaultSort: "due",
  pageSize: 25,
});

/** The deadlines list's URL names on the deadlines block's list. */
export const deadlineMap: EntityListMap = {
  sorts: {
    // The nearest date first.
    due: { by: "dueOn", direction: "asc" },
    newest: { by: "createdAt", direction: "desc" },
  },
  filters: { group: "groupKey" },
  facets: { group: "groupKey" },
};
