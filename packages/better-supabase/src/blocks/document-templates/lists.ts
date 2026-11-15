import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `templatePage`, `templateFacets` and `templateCount` accept for a
 * document template (ADR 0749, 1077). The manifest declares the same names, and
 * the SQL list function `page_document_templates` implements them. `active`
 * takes `"true"` or `"false"`, and `q` searches the name, the document type and
 * the body.
 */
export const documentTemplateListSurface: EntityListSurface = {
  sorts: ["name", "updatedAt"],
  facets: ["documentType", "active", "language"],
  filters: ["documentType", "legalEntityId", "language", "active"],
  search: ["name", "documentType", "body"],
};
