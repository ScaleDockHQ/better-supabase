import type {
  FilterCombinator,
  FilterNode,
  FilterOperatorSpec,
  FilterQuery,
  FilterRule,
} from "../../list/filter-query.ts";
import type { RuleField } from "./fields.ts";

import { FILTER_OPERATORS } from "../../list/filter-query.ts";

/** The operators a field allows, in the order the editor lists them. */
export function ruleOperators(field: RuleField): readonly FilterOperatorSpec[] {
  const allowed = field.operators;

  return FILTER_OPERATORS[field.type].filter(
    (entry) => allowed === undefined || allowed.includes(entry.value),
  );
}

/** An empty `and` group, the tree a new rule starts with. */
export const emptyConditions = (id = "root"): FilterQuery => ({
  id,
  type: "group",
  combinator: "and",
  rules: [],
});

/** The node with `id`, or `undefined`. */
export function findNode(tree: FilterNode, id: string): FilterNode | undefined {
  if (tree.id === id) {
    return tree;
  }

  if (tree.type === "rule") {
    return undefined;
  }

  for (const child of tree.rules) {
    const found = findNode(child, id);

    if (found !== undefined) {
      return found;
    }
  }

  return undefined;
}

/** The group that holds `id`, or `undefined` for the root and unknown ids. */
export function parentOf(
  tree: FilterQuery,
  id: string,
): FilterQuery | undefined {
  for (const child of tree.rules) {
    if (child.id === id) {
      return tree;
    }

    if (child.type === "group") {
      const found = parentOf(child, id);

      if (found !== undefined) {
        return found;
      }
    }
  }

  return undefined;
}

/** Whether `id` is `ancestor` or sits anywhere under it. */
export function contains(ancestor: FilterNode, id: string): boolean {
  return findNode(ancestor, id) !== undefined;
}

function mapTree(
  tree: FilterQuery,
  visit: (node: FilterNode) => FilterNode | null,
): FilterQuery {
  const walk = (node: FilterNode): FilterNode | null => {
    const next = visit(node);

    if (next === null || next.type === "rule") {
      return next;
    }

    const rules = next.rules.flatMap((child) => walk(child) ?? []);

    const same =
      rules.length === next.rules.length &&
      rules.every((child, index) => child === next.rules[index]);

    return same ? next : { ...next, rules };
  };

  const root = walk(tree);

  return root?.type === "group" ? root : tree;
}

/** Replaces the node with `id` by what `change` returns. */
export function updateNode(
  tree: FilterQuery,
  id: string,
  change: (node: FilterNode) => FilterNode,
): FilterQuery {
  return mapTree(tree, (node) => (node.id === id ? change(node) : node));
}

/** Drops the node with `id` and everything under it; the root stays. */
export function removeNode(tree: FilterQuery, id: string): FilterQuery {
  if (tree.id === id) {
    return tree;
  }

  return mapTree(tree, (node) => (node.id === id ? null : node));
}

/**
 * Adds `node` to the group `parent` at `index` (the end by default). Unchanged
 * when `parent` isn't a group in the tree.
 */
export function insertNode(
  tree: FilterQuery,
  parent: string,
  node: FilterNode,
  index?: number,
): FilterQuery {
  return mapTree(tree, (current) => {
    if (current.id !== parent || current.type !== "group") {
      return current;
    }

    const rules = [...current.rules];

    const at =
      index === undefined
        ? rules.length
        : Math.max(0, Math.min(index, rules.length));

    rules.splice(at, 0, node);

    return { ...current, rules };
  });
}

/**
 * Moves the node with `id` into the group `parent`, where it ends up at `index`
 * (as `arrayMove` counts it). Unchanged for the root, an unknown node or group,
 * or a move into the node itself.
 */
export function moveNode(
  tree: FilterQuery,
  id: string,
  parent: string,
  index: number,
): FilterQuery {
  const node = findNode(tree, id);
  const target = findNode(tree, parent);

  if (
    node === undefined ||
    parentOf(tree, id) === undefined ||
    target?.type !== "group" ||
    contains(node, parent)
  ) {
    return tree;
  }

  return insertNode(removeNode(tree, id), parent, node, index);
}

/** Changes a group's `and` or `or`. */
export function setCombinator(
  tree: FilterQuery,
  id: string,
  combinator: FilterCombinator,
): FilterQuery {
  return updateNode(tree, id, (node) =>
    node.type === "group" ? { ...node, combinator } : node,
  );
}

const arityOf = (
  field: RuleField | undefined,
  operator: string,
): FilterOperatorSpec["arity"] | undefined =>
  field === undefined
    ? undefined
    : FILTER_OPERATORS[field.type].find((entry) => entry.value === operator)
        ?.arity;

function withoutValue(rule: FilterRule): FilterRule {
  const { value: _value, ...rest } = rule;

  return rest;
}

/**
 * Points a rule at another field. A field of the same type keeps the operator
 * it allows, and its value; another type starts at the field's first operator
 * without a value.
 */
export function setRuleField(
  rule: FilterRule,
  field: RuleField,
  previous: RuleField | undefined,
): FilterRule {
  const operators = ruleOperators(field);

  const keep =
    previous?.type === field.type &&
    operators.some((entry) => entry.value === rule.operator);

  const path = field.id.split(".");

  return keep
    ? { ...rule, path }
    : withoutValue({ ...rule, path, operator: operators[0]?.value ?? "" });
}

/**
 * Changes a rule's operator. The value stays when the new operator takes the
 * same kind of value (one, many or a range), and is dropped otherwise.
 */
export function setRuleOperator(
  rule: FilterRule,
  operator: string,
  field: RuleField | undefined,
): FilterRule {
  const same = arityOf(field, rule.operator) === arityOf(field, operator);
  const next = { ...rule, operator };

  return same && arityOf(field, operator) !== "none"
    ? next
    : withoutValue(next);
}
