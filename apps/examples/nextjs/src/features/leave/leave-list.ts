import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

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
  sorts: ["start", "newest"],
  defaultSort: "start",
  pageSize: 25,
});

/** The leave list's URL names on the leave block's request list. */
export const leaveMap: EntityListMap = {
  sorts: {
    // Next leave first: the latest start date, as before.
    start: { by: "startsOn", direction: "desc" },
    newest: { by: "createdAt", direction: "desc" },
  },
  filters: { type: "typeId" },
  facets: { type: "typeId" },
};
