import type { ValidationIssue } from "../core/errors.ts";
import type { FilterQuery } from "../list/filter-query.ts";
import type { TableMeta } from "../schema/types.ts";

import {
  checkFilterQuery,
  filterWhere,
  tableFilterFields,
} from "../list/filter-query.ts";

/** How deep and wide a filter tree in `where` may be. */
const FILTER_TREE_LIMITS = {
  maxDepth: 8,
  maxRules: 200,
  maxValueLength: 1000,
  maxValues: 1000,
} as const;

/** What a filter tree in `where` turns into. */
export type FilterTreeWhere =
  | { readonly where: Record<string, unknown> | undefined }
  | { readonly issue: string };

/**
 * A filter tree from ReUI's Filters as a `where` object, checked against the
 * table's filterable columns.
 */
export function filterTreeWhere(
  table: TableMeta,
  input: FilterQuery,
): FilterTreeWhere {
  const fields = tableFilterFields(table);
  const issues: ValidationIssue[] = [];
  const query = checkFilterQuery(input, fields, FILTER_TREE_LIMITS, issues);
  const [issue] = issues;

  if (issue !== undefined) {
    return { issue: issue.message };
  }

  return {
    where: query === undefined ? undefined : filterWhere(query, fields),
  };
}
