import type { DriveDocumentStatus } from "better-supabase/blocks/drive";

import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

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

/** The register's URL names on the drive block's document list. */
export const registerMap: EntityListMap = {
  sorts: {
    number: { by: "number" },
    name: { by: "name" },
    // The nearest review first.
    review: { by: "nextReviewOn" },
  },
};
