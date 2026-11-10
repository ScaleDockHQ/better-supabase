import type { ValidationIssue } from "../core/errors.ts";
import type { FilterQuery } from "../list/filter-query.ts";
import type { TableMeta } from "../schema/types.ts";
import type { FilterTreeWhere } from "./filter-slot.ts";

import {
  checkFilterQuery,
  filterWhere,
  tableFilterFields,
} from "../list/filter-query.ts";
import { provideFilterTrees } from "./filter-slot.ts";

/** How deep and wide a filter tree in `where` may be. */
const FILTER_TREE_LIMITS = {
  maxDepth: 8,
  maxRules: 200,
  maxValueLength: 1000,
  maxValues: 1000,
} as const;

/**
 * A filter tree from ReUI's Filters as a `where` object, checked against the
 * table's filterable columns.
 */
function filterTreeWhere(
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

/**
 * Lets `where` take a filter tree (`FilterQuery` from ReUI's Filters). The
 * server installs it; a browser bundle that passes a tree to a read calls it
 * once, which ships the filter checks.
 */
export function enableFilterTrees(): void {
  provideFilterTrees(filterTreeWhere);
}
