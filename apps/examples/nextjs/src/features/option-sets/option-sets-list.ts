import { defineAdminList } from "@/lib/admin-list";

/** `/settings/option-sets?q=&state=&sort=&after=`. */
export const optionSetList = defineAdminList({
  facets: { state: ["active", "archived"] },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One option set as the overview and the list route send it. */
export interface OptionSetRow {
  readonly id: string;
  readonly name: string;
  readonly subjectType: string;
  readonly field: string;
  readonly isDefault: boolean;
  readonly archived: boolean;
  readonly items: number;
  readonly createdAt: string;
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
