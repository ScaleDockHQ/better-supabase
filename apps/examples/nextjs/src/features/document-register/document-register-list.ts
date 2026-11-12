import type { DriveDocumentStatus } from "better-supabase/blocks/drive";

import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

/** One controlled document, as the register and its list route send it. */
export interface RegisterRow {
  readonly id: string;
  readonly number: string;
  readonly name: string;
  readonly type: string;
  readonly status: DriveDocumentStatus;
  readonly effectiveVersion: number | null;
  /** ISO 8601 date. */
  readonly nextReviewOn: string | null;
  readonly reviewDue: boolean;
}

export const registerList = defineBlockList({
  facets: ["type", "status", "review"],
  sorts: ["number", "name", "review"],
  defaultSort: "number",
  pageSize: 25,
});

export const registerSpec: BlockListSpec<RegisterRow> = {
  text: (row) => [row.number, row.name, row.type],
  facets: {
    type: (row) => row.type,
    status: (row) => row.status,
    review: (row) => (row.reviewDue ? "due" : "ok"),
  },
  sorts: {
    number: (a, b) => a.number.localeCompare(b.number),
    name: (a, b) => a.name.localeCompare(b.name),
    // The nearest review first; documents without one last.
    review: (a, b) =>
      (a.nextReviewOn ?? "9999").localeCompare(b.nextReviewOn ?? "9999"),
  },
};
