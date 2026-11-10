import { createLoader, parseAsString } from "nuqs/server";

/**
 * The audit page's URL state, shared by the page (through `loadAuditFilters`)
 * and the filter bar. `before` is the keyset cursor of an older page,
 * `occurredAt|id`; `entry` opens one entry's details.
 */
export const auditSearchParams = {
  actor: parseAsString,
  type: parseAsString,
  from: parseAsString,
  to: parseAsString,
  q: parseAsString.withDefault(""),
  before: parseAsString,
  entry: parseAsString,
};

export const loadAuditFilters = createLoader(auditSearchParams);

/** The days a page covers when the URL names no start. */
export const DEFAULT_WINDOW_DAYS = 30;

/** Entries per page. */
export const AUDIT_PAGE_SIZE = 50;

/** The total stops counting here, and the page says "10,000+". */
export const AUDIT_COUNT_CAP = 10_000;
