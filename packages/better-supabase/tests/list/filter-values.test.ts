import { describe, expect, it } from "vitest";

import type { ValidationIssue } from "../../src/core/errors.ts";
import type { ColumnMeta, TableMeta } from "../../src/schema/types.ts";

import {
  checkFilterQuery,
  filterFieldsOf,
} from "../../src/list/filter-query.ts";
import { schema } from "../fixtures/generated-camel.ts";

const column = (
  db: string,
  type: string,
  extra: Partial<ColumnMeta> = {},
): ColumnMeta => ({ db, type, nullable: true, hasDefault: false, ...extra });

const customers = schema.meta.tables["customers"];

if (!customers) {
  throw new Error("No fixture table customers");
}

const items: TableMeta = {
  ...customers,
  key: "items",
  name: "items",
  columns: {
    title: column("title", "text"),
    qty: column("qty", "int4"),
    done: column("done", "bool"),
    due: column("due", "date"),
    labels: column("labels", "text", { array: true }),
    kind: column("kind", "text"),
  },
};

const fields = filterFieldsOf(items, {
  title: { type: "text", description: "The item's title" },
  qty: { type: "number", defaultOperator: "gt" },
  done: { type: "boolean" },
  due: { type: "date" },
  labels: { type: "multiselect", options: ["red", { value: "blue" }] },
  kind: { type: "select", options: [{ value: "a", label: "A" }] },
});

const LIMITS = { maxDepth: 4, maxRules: 50, maxValueLength: 5, maxValues: 2 };

function check(node: unknown): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  checkFilterQuery(
    { id: "g", type: "group", combinator: "and", rules: [node] },
    fields,
    LIMITS,
    issues,
  );

  return issues;
}

const rule = (path: string, operator: string, value?: unknown) => ({
  id: "r",
  type: "rule",
  path: [path],
  operator,
  value,
});

describe("filter field configs", () => {
  it("keeps descriptions, default operators and option labels", () => {
    const byId = Object.fromEntries(fields.map((field) => [field.id, field]));
    expect(byId["title"]?.description).toBe("The item's title");
    expect(byId["qty"]?.defaultOperator).toBe("gt");
    expect(byId["labels"]?.options).toEqual([
      { value: "red", label: "red" },
      { value: "blue", label: "blue" },
    ]);
    expect(byId["kind"]?.options).toEqual([{ value: "a", label: "A" }]);
  });

  it("rejects a type its column can't hold and an unknown default operator", () => {
    expect(() => filterFieldsOf(items, { title: { type: "number" } })).toThrow(
      /numeric/,
    );
    expect(() => filterFieldsOf(items, { title: { type: "boolean" } })).toThrow(
      /bool/,
    );
    expect(() =>
      filterFieldsOf(items, {
        qty: { type: "number", operators: ["eq"], defaultOperator: "gt" },
      }),
    ).toThrow(/defaultOperator/);
    expect(() =>
      filterFieldsOf(items, { title: { type: "unknown" as never } }),
    ).toThrow(/type must be one of/);
  });
});

describe("filter values", () => {
  it.each([
    ["a long text", rule("title", "contains", "toolong"), /At most 5/],
    ["text that is not text", rule("title", "contains", 1), /Must be text/],
    ["a missing value", rule("title", "contains"), /Needs a value/],
    ["a number as text", rule("qty", "eq", "3"), /Must be a number/],
    ["an infinite number", rule("qty", "eq", Infinity), /Must be a number/],
    ["a range of one", rule("qty", "between", [1]), /two values/],
    ["a range with text", rule("qty", "between", [1, "x"]), /number/],
    ["a boolean as a word", rule("done", "is", "yes"), /true or false/],
    ["a date as text", rule("due", "is", "2026-10-13"), /date value/],
    ["both date and relative", rule("due", "is", {}), /either date/],
    [
      "an impossible day",
      rule("due", "is", { date: "2026-02-30" }),
      /yyyy-MM-dd/,
    ],
    [
      "a malformed day",
      rule("due", "is", { date: "13-10-2026" }),
      /yyyy-MM-dd/,
    ],
    [
      "an unknown unit",
      rule("due", "is", { relative: { unit: "hour", offset: 1 } }),
      /relative/,
    ],
    [
      "a fractional offset",
      rule("due", "is", { relative: { unit: "day", offset: 1.5 } }),
      /relative/,
    ],
    [
      "a huge offset",
      rule("due", "is", { relative: { unit: "day", offset: 200_000 } }),
      /relative/,
    ],
    [
      "a bad time",
      rule("due", "is", { date: "2026-10-13", time: "25:00" }),
      /HH:mm/,
    ],
    ["an empty list", rule("labels", "has_any_of", []), /list of values/],
    [
      "too many values",
      rule("labels", "has_any_of", ["red", "blue", "red"]),
      /At most 2/,
    ],
    [
      "an unknown option",
      rule("labels", "has_any_of", ["green"]),
      /one of: red, blue/,
    ],
    ["an empty select value", rule("kind", "is", ""), /Must be a value/],
    ["a long select value", rule("kind", "is", "abcdef"), /At most 5/],
  ])("rejects %s", (_name, node, message) => {
    const issues = check(node);
    expect(issues).toHaveLength(1);
    expect(issues[0]?.message).toMatch(message);
    expect(issues[0]?.path?.at(-1)).toBe("value");
  });

  it("accepts each type's values", () => {
    expect(
      check({
        id: "g2",
        type: "group",
        combinator: "or",
        rules: [
          rule("title", "contains", "abc"),
          rule("qty", "between", [1, 2]),
          rule("done", "is", "true"),
          rule("due", "is", { date: "2024-02-29", time: "09:30" }),
          rule("due", "is_before", { relative: { unit: "week", offset: -1 } }),
          rule("labels", "has_all_of", ["red", "blue"]),
          rule("kind", "is", "a"),
          rule("title", "empty"),
        ],
      }),
    ).toEqual([]);
  });

  it("reports bad nodes at their path", () => {
    expect(check("x")[0]?.message).toMatch(/group or rule/);
    expect(check({ type: "rule" })[0]?.message).toMatch(/id/);
    expect(check({ id: "x", type: "other" })[0]?.message).toMatch(/type must/);
    expect(
      check({ id: "x", type: "group", combinator: "xor", rules: [] })[0]?.path,
    ).toContain("combinator");
    expect(
      check({ id: "x", type: "group", combinator: "and", rules: {} })[0]?.path,
    ).toContain("rules");
    expect(
      check({ ...rule("title", "contains", "a"), path: [] })[0]?.path,
    ).toContain("path");
    expect(
      check({ ...rule("title", "contains", "a"), operator: 1 })[0]?.path,
    ).toContain("operator");
    expect(
      check({ ...rule("title", "contains", "a"), negated: "yes" })[0]?.path,
    ).toContain("negated");
  });
});
