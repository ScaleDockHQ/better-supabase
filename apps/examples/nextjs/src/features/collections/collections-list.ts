import { defineBlockList } from "@/lib/block-status-list";

export const COLLECTION_SCOPE_VALUES = ["user", "team", "tenant"] as const;
export const COLLECTION_STATE_VALUES = ["active", "archived"] as const;

export const COLLECTION_PAGE_SIZE = 50;

/**
 * `/shop/collections?scope=&state=`. The collections block pages by keyset and
 * takes the scopes as one list filter; the archive state picks whether archived
 * collections are read at all.
 */
export const collectionList = defineBlockList({
  facets: [
    { key: "scope", values: COLLECTION_SCOPE_VALUES },
    { key: "state", values: COLLECTION_STATE_VALUES },
  ],
  sorts: ["newest"],
  defaultSort: "newest",
});
