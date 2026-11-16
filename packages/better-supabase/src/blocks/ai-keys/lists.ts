import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `keys.page`, `keys.facets` and `keys.count` accept (ADR 0749, 1077). The
 * SQL list function `page_ai_provider_keys` implements them. `enabled` takes
 * `"true"` or `"false"`. `q` searches the provider and the name. The default
 * order is by provider, then name.
 */
export const keyListSurface: EntityListSurface = {
  sorts: ["provider", "name", "createdAt"],
  facets: ["provider", "enabled"],
  filters: ["provider", "enabled"],
  search: ["provider", "name"],
};

/**
 * What `batches.page`, `batches.facets` and `batches.count` accept. The SQL
 * list function `page_ai_batches` implements them. A batch has no text column,
 * so `q` is not declared. The default order is newest first.
 */
export const batchListSurface: EntityListSurface = {
  sorts: ["createdAt", "provider", "status"],
  facets: ["status", "provider"],
  filters: ["status", "provider"],
};
