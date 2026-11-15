import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `accountPage`, `accountFacets` and `accountCount` accept for an
 * accounting account (ADR 0749, 1077). Archived accounts are hidden unless
 * `archived` is `["true"]` (only the archived ones). The SQL list function is
 * `page_accounting_accounts`; row level security decides who reads.
 */
export const accountingAccountListSurface: EntityListSurface = {
  sorts: ["code", "name"],
  facets: ["type", "active"],
  filters: ["type", "active", "archived"],
  search: ["code", "name"],
};

/**
 * The same for an entry (`page_accounting_entries`), newest entry date first.
 * `since` and `until` take a date (`2026-01-31`) and bound the entry date.
 */
export const accountingEntryListSurface: EntityListSurface = {
  sorts: ["entryDate", "createdAt"],
  facets: ["status"],
  filters: ["status", "journalId", "since", "until"],
  search: ["number", "reference", "memo"],
};
