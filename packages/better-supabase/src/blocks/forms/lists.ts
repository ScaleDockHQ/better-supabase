import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a form (ADR 0749). The manifest
 * declares the same names, and the SQL list function `list_forms` implements
 * them.
 */
export const formListSurface: EntityListSurface = {
  sorts: ["createdAt", "title", "key"],
  facets: ["status"],
  filters: ["status"],
  search: ["title", "key"],
};

/**
 * What `submissionPage`, `submissionFacets` and `submissionCount` accept for a
 * form submission (ADR 1077). The SQL list function `page_form_submissions`
 * implements them. Reviewers see every submission and other callers their own.
 * `includeArchived` takes `"true"`, and `q` is a text match in the answers.
 */
export const formSubmissionListSurface: EntityListSurface = {
  sorts: ["createdAt", "submittedAt"],
  facets: ["status", "formId"],
  filters: ["formId", "status", "respondentId", "includeArchived"],
  search: ["answers"],
};
