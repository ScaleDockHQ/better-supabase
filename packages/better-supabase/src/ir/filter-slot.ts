import type { FilterQuery } from "../list/filter-query.ts";
import type { TableMeta } from "../schema/types.ts";

/** What a filter tree in `where` turns into. */
export type FilterTreeWhere =
  | { readonly where: Record<string, unknown> | undefined }
  | { readonly issue: string };

export type FilterTreeResolver = (
  table: TableMeta,
  input: FilterQuery,
) => FilterTreeWhere;

// Kept apart from the converter so the query builder does not bundle the
// filter field checks (ADR 0645); the server runtime and
// `enableFilterTrees()` fill it.
let resolver: FilterTreeResolver | undefined;

/** Installs the converter from filter trees to `where` objects. */
export function provideFilterTrees(resolve: FilterTreeResolver): void {
  resolver ??= resolve;
}

/** The `where` for a tree, or `undefined` when no converter is installed. */
export function resolveFilterTree(
  table: TableMeta,
  input: FilterQuery,
): FilterTreeWhere | undefined {
  return resolver?.(table, input);
}

/** A filter tree, as a `where` may be: a root group with its rules. */
export function isFilterTree(value: unknown): value is FilterQuery {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  // SAFETY: the check above narrowed value to a non-null object.
  const record = value as Record<string, unknown>;

  return (
    record["type"] === "group" &&
    (record["combinator"] === "and" || record["combinator"] === "or") &&
    typeof record["id"] === "string" &&
    Array.isArray(record["rules"])
  );
}
