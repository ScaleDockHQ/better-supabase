import { defineBlockList } from "@/lib/block-status-list";

export const COLLECTION_SCOPE_VALUES = ["user", "team", "tenant"] as const;
export const COLLECTION_STATE_VALUES = ["active", "archived"] as const;

/**
 * `/shop/collections?scope=&state=`. The collections block lists every
 * collection of the caller's organization in one call and takes no cursor, so
 * the scope and archive filters apply to that list on the server.
 */
export const collectionList = defineBlockList({
  facets: [
    { key: "scope", values: COLLECTION_SCOPE_VALUES },
    { key: "state", values: COLLECTION_STATE_VALUES },
  ],
  sorts: ["newest"],
  defaultSort: "newest",
});
