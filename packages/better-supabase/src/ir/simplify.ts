import type { Condition } from './types.ts';

/**
 * Folds constant conditions. `true` means "no filter", `false` means "matches
 * nothing", so executors can skip the request entirely.
 */
export function simplify(
  condition: Condition | undefined,
): Condition | boolean {
  if (condition === undefined) return true;
  switch (condition.kind) {
    case 'and': {
      const items: Condition[] = [];
      for (const item of condition.items) {
        const simple = simplify(item);
        if (simple === false) return false;
        if (simple !== true) items.push(simple);
      }
      if (items.length === 0) return true;
      return items.length === 1 && items[0] ? items[0] : { kind: 'and', items };
    }
    case 'or': {
      const items: Condition[] = [];
      for (const item of condition.items) {
        const simple = simplify(item);
        if (simple === true) return true;
        if (simple !== false) items.push(simple);
      }
      if (items.length === 0) return false;
      return items.length === 1 && items[0] ? items[0] : { kind: 'or', items };
    }
    case 'not': {
      const inner = simplify(condition.item);
      if (typeof inner === 'boolean') return !inner;
      if (inner.kind === 'not') return inner.item;
      return { kind: 'not', item: inner };
    }
    case 'relation': {
      const where = simplify(condition.where);
      if (where === true) {
        // every(true) holds for every parent row.
        if (condition.quantifier === 'every') return true;
        return { ...condition, where: undefined };
      }
      if (where === false) {
        // some(false) matches nothing, none(false) matches everything and
        // every(false) holds only when there are no related rows.
        if (condition.quantifier === 'some') return false;
        if (condition.quantifier === 'none') return true;
        return { ...condition, quantifier: 'none', where: undefined };
      }
      return { ...condition, where };
    }
    case 'column':
      if (
        condition.op === 'in' &&
        Array.isArray(condition.value) &&
        condition.value.length === 0
      ) {
        return false;
      }
      return condition;
    default: {
      const exhaustive: never = condition;
      return exhaustive;
    }
  }
}

/** Returns the condition, or `undefined` when it folds to `true`. */
export function simplifyOrFalse(
  condition: Condition | undefined,
):
  | { readonly never: true }
  | { readonly never: false; readonly condition: Condition | undefined } {
  const simple = simplify(condition);
  if (simple === false) return { never: true };
  return { never: false, condition: simple === true ? undefined : simple };
}
