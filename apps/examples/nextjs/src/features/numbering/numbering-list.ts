import { defineAdminList } from "@/lib/admin-list";

/** `/settings/numbering?q=entity=&sort=&after=`. */
export const numberingList = defineAdminList({
  facets: { entity: [] },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One row as the overview and the list route send it. */
export interface NumberingRow {
  readonly id: string;
  readonly entity: string;
  readonly period: string;
  readonly scope: string | null;
  readonly lastNumber: number;
  readonly updatedAt: string;
}
