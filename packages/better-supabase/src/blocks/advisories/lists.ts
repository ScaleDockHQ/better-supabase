import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the advisory `page`, `facets` and `count` accept (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_advisories`
 * implements them.
 */
export const advisoryListSurface: EntityListSurface = {
  sorts: ["createdAt", "trackingId", "title"],
  facets: ["status", "severity"],
  filters: ["status", "severity", "productId"],
  search: ["title", "trackingId", "summary"],
};

/** The same for a tracked vulnerability, over `page_vulnerabilities`. */
export const vulnerabilityListSurface: EntityListSurface = {
  sorts: ["vulnId", "cvssScore", "epssScore"],
  facets: ["severity"],
  filters: ["severity", "kev"],
  search: ["vulnId", "summary"],
};
