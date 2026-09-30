import type { TableMeta } from "../schema/types.ts";

import {
  and,
  type Condition,
  type Include,
  not,
  type Operation,
  type Selection,
} from "./types.ts";

/** Returns the filter that always applies to rows of `table`, if any. */
export type ScopeFor = (table: TableMeta) => Condition | undefined;

/**
 * Applies `scopeFor` to every relation filter in a condition. `every(W)`
 * becomes `none(S and not W)` so out-of-scope rows (soft-deleted, other
 * tenants) neither satisfy nor fail it.
 */
export function scopeCondition(
  condition: Condition | undefined,
  scopeFor: ScopeFor,
): Condition | undefined {
  if (!condition) return undefined;
  switch (condition.kind) {
    case "and":
    case "or":
      return {
        kind: condition.kind,
        items: condition.items.map(
          (item) => scopeCondition(item, scopeFor) ?? item,
        ),
      };
    case "not":
      return {
        kind: "not",
        item: scopeCondition(condition.item, scopeFor) ?? condition.item,
      };
    case "column":
      return condition;
    case "relation": {
      const inner = scopeCondition(condition.where, scopeFor);
      const scope = scopeFor(condition.target);
      if (!scope) return { ...condition, where: inner };
      switch (condition.quantifier) {
        case "some":
        case "none":
          return { ...condition, where: and(inner, scope) };
        case "every":
          return inner
            ? {
                ...condition,
                quantifier: "none",
                where: and(scope, not(inner)),
              }
            : { ...condition, where: undefined };
        default: {
          const exhaustive: never = condition.quantifier;
          return exhaustive;
        }
      }
    }
    default: {
      const exhaustive: never = condition;
      return exhaustive;
    }
  }
}

function scopeInclude(include: Include, scopeFor: ScopeFor): Include {
  return {
    ...include,
    selection: scopeSelection(include.selection, scopeFor),
    where: and(
      scopeCondition(include.where, scopeFor),
      scopeFor(include.target),
    ),
  };
}

/** Applies `scopeFor` to every include and to filters inside includes. */
export function scopeSelection(
  selection: Selection,
  scopeFor: ScopeFor,
): Selection {
  if (selection.includes.length === 0) return selection;
  return {
    ...selection,
    includes: selection.includes.map((include) =>
      scopeInclude(include, scopeFor),
    ),
  };
}

/**
 * Scopes a whole operation: the root table's rows (reads, updates, deletes),
 * relation filters, includes and returned embeds. Inserts only get their
 * returning selection scoped.
 */
export function scopeOperation(
  op: Operation,
  scopeFor: ScopeFor,
  root = true,
): Operation {
  const own = root ? scopeFor(op.table) : undefined;
  switch (op.kind) {
    case "select":
      return {
        ...op,
        selection: scopeSelection(op.selection, scopeFor),
        where: and(scopeCondition(op.where, scopeFor), own),
      };
    case "update":
    case "delete":
      return {
        ...op,
        where: and(scopeCondition(op.where, scopeFor), own),
        returning: op.returning
          ? scopeSelection(op.returning, scopeFor)
          : undefined,
      };
    case "insert":
      return {
        ...op,
        returning: op.returning
          ? scopeSelection(op.returning, scopeFor)
          : undefined,
      };
    default: {
      const exhaustive: never = op;
      return exhaustive;
    }
  }
}
