import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the observation `page`, `facets` and `count` accept (ADR 0749, 1077).
 * The manifest declares the same names, and the SQL list function
 * `page_observations` implements them.
 */
export const observationListSurface: EntityListSurface = {
  sorts: ["observedAt", "createdAt"],
  facets: ["status", "definitionKey"],
  filters: ["subjectType", "subjectId", "definitionKey", "status"],
};

/** The same for a definition, over `page_observation_definitions`. */
export const observationDefinitionListSurface: EntityListSurface = {
  sorts: ["title", "key"],
  facets: ["valueType", "scope"],
  filters: ["valueType", "scope", "archived"],
  search: ["title", "key"],
};
