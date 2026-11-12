import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

/** One request of the leave overview, as the page and the list route send it. */
export interface LeaveRow {
  readonly id: string;
  readonly who: string;
  readonly typeId: string;
  readonly typeName: string;
  readonly unit: "days" | "hours";
  readonly startsOn: string;
  readonly endsOn: string;
  readonly amount: number;
  readonly status: "pending" | "approved" | "rejected" | "cancelled";
  readonly approvalId: string | null;
  readonly note: string | null;
}

export const leaveList = defineBlockList({
  facets: ["status", "type"],
  sorts: ["start", "newest", "name"],
  defaultSort: "start",
  pageSize: 25,
});

export const leaveSpec: BlockListSpec<LeaveRow> = {
  text: (row) => [row.who, row.typeName, row.note],
  facets: { status: (row) => row.status, type: (row) => row.typeId },
  sorts: {
    // Next leave first: the soonest start date, requests already over last.
    start: (a, b) => b.startsOn.localeCompare(a.startsOn),
    newest: (a, b) => b.endsOn.localeCompare(a.endsOn),
    name: (a, b) => a.who.localeCompare(b.who),
  },
};
