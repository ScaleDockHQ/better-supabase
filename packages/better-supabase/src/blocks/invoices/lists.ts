import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an invoice (ADR 0749, 1077).
 * `subjectType` with `subjectId` reads the invoices of one record, as `list`
 * does. The SQL list function is `page_invoices`; rows the caller can't read
 * stay out. Listing needs `invoices.read`.
 */
export const invoiceListSurface: EntityListSurface = {
  sorts: ["createdAt", "dueOn", "total"],
  facets: ["status", "currency"],
  filters: ["status", "currency", "kind", "subjectType", "subjectId"],
  search: ["number"],
};
