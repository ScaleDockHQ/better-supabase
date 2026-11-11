import type { BlockListSpec } from "@/lib/block-list";

import { defineBlockList } from "@/lib/block-list";

/** One template slot of a document type, as the page and the list route send it. */
export interface TemplateRow {
  readonly id: string;
  readonly name: string;
  readonly documentType: string;
  readonly language: string | null;
  readonly version: number;
  readonly active: boolean;
  readonly updatedAt: string;
}

export const templateList = defineBlockList({
  facets: ["type", "active"],
  sorts: ["name", "newest"],
  defaultSort: "name",
  pageSize: 25,
});

export const templateSpec: BlockListSpec<TemplateRow> = {
  text: (row) => [row.name, row.documentType, row.language],
  facets: {
    type: (row) => row.documentType,
    active: (row) => (row.active ? "active" : "inactive"),
  },
  sorts: {
    name: (a, b) =>
      a.documentType.localeCompare(b.documentType) ||
      a.name.localeCompare(b.name),
    newest: (a, b) => b.updatedAt.localeCompare(a.updatedAt),
  },
};
