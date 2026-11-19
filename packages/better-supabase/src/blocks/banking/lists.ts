import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `accountPage`, `accountFacets` and `accountCount` accept for a bank
 * account (ADR 0749, 1077). Archived accounts are hidden unless `archived` is
 * `["true"]` (only the archived ones). The SQL list function is
 * `page_bank_accounts`.
 */
export const bankAccountListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "position"],
  facets: ["currency"],
  filters: ["currency", "archived"],
  search: ["name", "iban", "holder"],
};

/**
 * The same for a payment batch (`page_payment_batches`), newest first by
 * default.
 */
export const paymentBatchListSurface: EntityListSurface = {
  sorts: ["createdAt", "executionOn"],
  facets: ["status", "currency"],
  filters: ["status", "accountId", "currency"],
  search: ["reference", "messageId"],
};
