import { defineBlockList } from "@/lib/block-list-url";

/** `/settings/search?q=type=&sort=&after=`. */
export const searchDocumentList = defineBlockList({
  facets: ["type"],
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One row as the overview and the list route send it. */
export interface SearchDocumentRow {
  readonly id: string;
  readonly title: string;
  readonly subjectType: string;
  readonly url: string | null;
  readonly updatedAt: string;
}
