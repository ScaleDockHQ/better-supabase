import { describe, expect, it } from "vitest";

import type { RuleField } from "../../../src/blocks/rules/fields.ts";
import type {
  FilterQuery,
  FilterRule,
} from "../../../src/list/filter-query.ts";

import {
  contains,
  emptyConditions,
  findNode,
  insertNode,
  moveNode,
  parentOf,
  removeNode,
  ruleOperators,
  setCombinator,
  setRuleField,
  setRuleOperator,
  updateNode,
} from "../../../src/blocks/rules/tree.ts";

const field = (
  id: string,
  type: RuleField["type"],
  operators?: readonly string[],
): RuleField => ({
  subjectType: "expense",
  id,
  label: id,
  description: undefined,
  type,
  column: id,
  columnType: type === "number" ? "numeric" : "text",
  nullable: false,
  options: undefined,
  operators,
});

const rule = (id: string, extra: Partial<FilterRule> = {}): FilterRule => ({
  id,
  type: "rule",
  path: ["amount"],
  operator: "gt",
  value: 10,
  ...extra,
});

const tree: FilterQuery = {
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    rule("a"),
    { id: "g", type: "group", combinator: "or", rules: [rule("b"), rule("c")] },
  ],
};

const ids = (group: FilterQuery): string[] =>
  group.rules.map((child) => child.id);

describe("rule tree", () => {
  it("finds nodes and their groups", () => {
    expect(findNode(tree, "c")?.id).toBe("c");
    expect(findNode(tree, "missing")).toBeUndefined();
    expect(parentOf(tree, "c")?.id).toBe("g");
    expect(parentOf(tree, "root")).toBeUndefined();
    expect(contains(tree, "b")).toBe(true);
    expect(contains(rule("a"), "b")).toBe(false);
  });

  it("updates, removes and inserts without touching the input", () => {
    const updated = updateNode(tree, "b", (node) => ({ ...node, id: "b2" }));
    expect(findNode(updated, "b2")).toBeDefined();
    expect(findNode(tree, "b2")).toBeUndefined();

    expect(ids(removeNode(tree, "g"))).toEqual(["a"]);
    expect(removeNode(tree, "root")).toBe(tree);

    const inserted = insertNode(tree, "root", rule("d"), 0);
    expect(ids(inserted)).toEqual(["d", "a", "g"]);
    expect(ids(insertNode(tree, "root", rule("e")))).toEqual(["a", "g", "e"]);
    expect(insertNode(tree, "a", rule("x"))).toBe(tree);
    expect(emptyConditions()).toEqual({
      id: "root",
      type: "group",
      combinator: "and",
      rules: [],
    });
  });

  it("moves nodes to their final index", () => {
    expect(ids(moveNode(tree, "a", "root", 1))).toEqual(["g", "a"]);

    const into = moveNode(tree, "a", "g", 1);
    expect(ids(into)).toEqual(["g"]);
    expect(findNode(into, "g")).toMatchObject({
      rules: [{ id: "b" }, { id: "a" }, { id: "c" }],
    });

    expect(moveNode(tree, "root", "g", 0)).toBe(tree);
    expect(moveNode(tree, "g", "g", 0)).toBe(tree);
    expect(moveNode(tree, "missing", "root", 0)).toBe(tree);
    expect(moveNode(tree, "a", "b", 0)).toBe(tree);
  });

  it("sets a group's combinator", () => {
    expect(findNode(setCombinator(tree, "g", "and"), "g")).toMatchObject({
      combinator: "and",
    });
    expect(setCombinator(tree, "a", "or")).toBe(tree);
  });

  it("lists a field's operators", () => {
    expect(ruleOperators(field("amount", "number"))[0]?.value).toBe("eq");
    expect(
      ruleOperators(field("amount", "number", ["gt", "lt"])).map(
        (operator) => operator.value,
      ),
    ).toEqual(["gt", "lt"]);
  });

  it("keeps the operator and value for a field of the same type", () => {
    const amount = field("amount", "number");
    const tax = field("totals.tax", "number");
    const note = field("note", "text");

    expect(setRuleField(rule("a"), tax, amount)).toMatchObject({
      path: ["totals", "tax"],
      operator: "gt",
      value: 10,
    });

    const changed = setRuleField(rule("a"), note, amount);
    expect(changed).toMatchObject({ path: ["note"], operator: "contains" });
    expect("value" in changed).toBe(false);
  });

  it("keeps the value only when the operator takes the same kind", () => {
    const amount = field("amount", "number");

    expect(setRuleOperator(rule("a"), "lt", amount)).toMatchObject({
      operator: "lt",
      value: 10,
    });
    expect("value" in setRuleOperator(rule("a"), "between", amount)).toBe(
      false,
    );
    expect("value" in setRuleOperator(rule("a"), "empty", amount)).toBe(false);
  });
});
