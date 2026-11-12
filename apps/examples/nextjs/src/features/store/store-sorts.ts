export const STORE_SORTS = [
  "newest",
  "price_asc",
  "price_desc",
  "title",
] as const;

export type StoreSort = (typeof STORE_SORTS)[number];
