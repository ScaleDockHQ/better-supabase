import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

/** `/settings/option-sets?q=&subjectType=&field=&sort=&after=`. */
export const optionSetList = defineBlockList({
  facets: ["subjectType", "field"],
  sorts: ["newest", "oldest", "name"],
  defaultSort: "newest",
  pageSize: 25,
});

/** The list's URL names on the option sets block's `setPage` and `setFacets`. */
export const optionSetMap: EntityListMap = {
  sorts: {
    newest: { by: "createdAt", direction: "desc" },
    oldest: { by: "createdAt", direction: "asc" },
    name: { by: "name" },
  },
};

/** One option set as the overview and the list route send it. */
export interface OptionSetRow {
  readonly id: string;
  readonly name: string;
  readonly subjectType: string;
  readonly field: string;
  readonly isDefault: boolean;
  readonly items: number;
}

/** One item of an option set, as the detail page sends it. */
export interface OptionItemRow {
  readonly id: string;
  readonly key: string;
  readonly label: string;
  readonly level: number;
  readonly color: string | null;
  readonly icon: string | null;
  readonly archived: boolean;
}
