import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a guardrail policy (ADR 1077).
 * The SQL list function `page_guardrail_policies` implements them. `q` searches
 * the agent. The default order is agent, then stage; without an organization
 * the page reads the system's policies.
 */
export const policyListSurface: EntityListSurface = {
  sorts: ["agent", "updatedAt"],
  facets: ["stage", "enabled"],
  filters: ["agent", "stage", "enabled"],
  search: ["agent"],
};

/**
 * What `page`, `facets` and `count` accept for a logged decision (ADR 1077).
 * `page_guardrail_decisions` implements them. `q` searches the agent. The
 * default order is newest first; without an organization the page reads every
 * organization's decisions, as `decisions.list` does.
 */
export const decisionListSurface: EntityListSurface = {
  sorts: ["createdAt", "agent"],
  facets: ["decision", "stage"],
  filters: ["agent", "decision", "stage"],
  search: ["agent"],
};
