import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

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

/** The list's URL names on the qualifications block's type list. */
export const qualificationTypeMap: EntityListMap = {
  sorts: { name: { by: "name" }, key: { by: "key" } },
};
