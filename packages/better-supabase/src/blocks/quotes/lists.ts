import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a quote (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_quotes`
 * implements them. Listing needs `quotes.read`.
 */
export const quoteListSurface: EntityListSurface = {
  sorts: ["createdAt", "validUntil", "title"],
  facets: ["status", "currency", "ownerId"],
  filters: ["status", "ownerId", "currency", "companyId", "contactId"],
  search: ["title", "identifier"],
};
