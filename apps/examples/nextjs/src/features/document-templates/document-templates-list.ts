import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

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

/** The templates list's URL names on the document templates block's list. */
export const templateMap: EntityListMap = {
  sorts: {
    name: { by: "name" },
    newest: { by: "updatedAt", direction: "desc" },
  },
  filters: { type: "documentType" },
  facets: { type: "documentType" },
};
