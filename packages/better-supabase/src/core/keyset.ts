import {
  and,
  column as columnIs,
  type Condition,
  not,
  or,
  type OrderTerm,
} from "../ir/types.ts";

/**
 * The rows after the cursor `values` in `orderBy` order, as an OR of ANDs:
 * `a > x or (a = x and b > y)`. The SQL compiler sends that shape as the row
 * comparison `(a, b) > (x, y)`. Nulls sort where Postgres puts them: last
 * for `asc`, first for `desc`, unless the term says otherwise.
 */
export function keysetCondition(
  orderBy: readonly OrderTerm[],
  values: readonly unknown[],
  nullable: (column: string) => boolean,
): Condition {
  const isNull = (name: string): Condition => columnIs(name, "is", null);
  const branches = orderBy.flatMap((term, index): Condition[] => {
    const value = values[index];
    const nullsFirst =
      (term.nulls ?? (term.direction === "desc" ? "first" : "last")) ===
      "first";
    const after = columnIs(
      term.column,
      term.direction === "asc" ? "gt" : "lt",
      value,
    );
    const step =
      value === null
        ? nullsFirst
          ? not(isNull(term.column))
          : undefined
        : nullsFirst || !nullable(term.column)
          ? after
          : or(after, isNull(term.column));
    if (!step) return [];
    const equal = orderBy
      .slice(0, index)
      .map((prev, prevIndex) =>
        values[prevIndex] === null
          ? isNull(prev.column)
          : columnIs(prev.column, "eq", values[prevIndex]),
      );
    return [and(...equal, step) ?? step];
  });
  // A null in the last nulls-last term leaves nothing after the cursor.
  return branches.length > 0
    ? or(...branches)
    : columnIs(orderBy[0]?.column ?? "", "in", []);
}
