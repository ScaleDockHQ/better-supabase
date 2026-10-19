import { describe, expect, test } from "vitest";

import {
  columnError,
  defaultError,
  isRollupAggregate,
  tableWithoutComputed,
} from "../../src/create/index.ts";

const preset = {
  scope: "tenant",
  tenantName: "organization",
  idType: "uuid",
} as const;

describe("isRollupAggregate", () => {
  test("accepts the aggregates and nothing else", () => {
    expect(isRollupAggregate("sum")).toBe(true);
    expect(isRollupAggregate("median")).toBe(false);
  });
});

describe("tableWithoutComputed", () => {
  test("drops the rollup or lookup with that name", () => {
    const table = {
      columns: {},
      rollups: {
        total: { table: "tasks", via: "project_id", aggregate: "count" },
      },
    } as const;

    expect(tableWithoutComputed(table, "total").rollups).toBeUndefined();
  });
});

describe("columnError and defaultError", () => {
  test("refuse a bad identifier and accept a free name", () => {
    expect(columnError({ columns: {} }, "Bad Name", preset)).toBeDefined();
    expect(columnError({ columns: {} }, "title", preset)).toBeUndefined();
  });

  test("defaultError allows an empty value and explains a wrong one", () => {
    expect(defaultError("integer", " ")).toBeUndefined();
    expect(defaultError("integer", "abc")).toMatch(/integer column/u);
  });
});
