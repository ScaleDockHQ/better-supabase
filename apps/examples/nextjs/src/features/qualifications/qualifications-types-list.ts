import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

/** One qualification type, as the list and the list route send it. */
export interface QualificationTypeRow {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly validForMonths: number | null;
  readonly evidenceRequired: boolean;
  readonly archived: boolean;
}

export const qualificationTypeList = defineBlockList({
  facets: ["expiry", "state"],
  sorts: ["name", "key"],
  defaultSort: "name",
  pageSize: 25,
});

export const qualificationTypeSpec: BlockListSpec<QualificationTypeRow> = {
  text: (row) => [row.name, row.key],
  facets: {
    expiry: (row) => (row.validForMonths === null ? "never" : "expires"),
    state: (row) => (row.archived ? "archived" : "active"),
  },
  sorts: {
    name: (a, b) => a.name.localeCompare(b.name),
    key: (a, b) => a.key.localeCompare(b.key),
  },
};
