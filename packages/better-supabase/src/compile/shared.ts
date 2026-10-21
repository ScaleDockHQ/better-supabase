import { invalidRequest } from "../ir/build.ts";

/** A row-count or offset value that is safe to inline into SQL text. */
export function integer(value: number): number {
  if (!Number.isInteger(value) || value < 0) {
    invalidRequest(`Expected a non-negative integer, got ${value}`);
  }

  return value;
}

/**
 * The ` where a and b` clause for the parts that are present, or an empty
 * string.
 */
export function whereClause(parts: readonly (string | undefined)[]): string {
  const present = parts.filter((part): part is string => part !== undefined);

  return present.length > 0 ? ` where ${present.join(" and ")}` : "";
}
