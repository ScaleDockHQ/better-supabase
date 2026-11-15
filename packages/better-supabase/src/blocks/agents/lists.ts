import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an agent (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_agents`
 * implements them. `mode` is one of `store` (the default), `mine` or
 * `installed`, passed as a list of one; `includeArchived` is a flag filter
 * (`["true"]` also reads archived agents). `q` searches the name and the
 * description. The default order is the newest published or updated agent
 * first.
 */
export const agentListSurface: EntityListSurface = {
  sorts: ["name", "updatedAt", "createdAt", "installCount"],
  facets: ["visibility"],
  filters: ["mode", "visibility", "includeArchived"],
  search: ["name", "description"],
};
