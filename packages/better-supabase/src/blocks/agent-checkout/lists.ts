import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `sessionPage`, `sessionFacets` and `sessionCount` accept for a checkout
 * session (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_checkout_sessions` implements them.
 */
export const checkoutSessionListSurface: EntityListSurface = {
  sorts: ["createdAt", "expiresAt"],
  facets: ["status", "protocol"],
  filters: ["status", "protocol", "cartId"],
};

/** The same for an agent mandate (`list_agent_mandates`). */
export const agentMandateListSurface: EntityListSurface = {
  sorts: ["createdAt", "expiresAt"],
  facets: ["status", "vct"],
  filters: ["sessionId", "status", "vct"],
};
