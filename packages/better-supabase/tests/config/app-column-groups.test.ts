import { describe, expect, it } from "vitest";

import { groupsOfColumn } from "../../src/config/app-column-groups.ts";
import { resolveConfig } from "../../src/config/index.ts";

const table = (columnGroups: unknown) => ({
  appTables: {
    projects: {
      columns: { budget: { type: "bigint" }, rate: { type: "bigint" } },
      columnGroups,
    },
  },
});

// SAFETY: the tests pass malformed groups on purpose to reach the validation.
const resolve = (columnGroups: unknown) =>
  resolveConfig(table(columnGroups) as never, "/app");

describe("appTables columnGroups", () => {
  it("keeps a valid group", () => {
    const groups = {
      money: { columns: ["budget", "rate"], update: "projects.budget" },
    };

    expect(resolve(groups).appTables["projects"]?.columnGroups).toEqual(groups);
  });

  it("refuses a column the table lacks", () => {
    expect(() =>
      resolve({ money: { columns: ["nope"], update: "projects.budget" } }),
    ).toThrow("tables.projects.columnGroups.money");
  });

  it("refuses a column in two groups", () => {
    expect(() =>
      resolve({
        a: { columns: ["budget"], update: "p.a" },
        b: { columns: ["budget"], update: "p.b" },
      }),
    ).toThrow("budget");
  });

  it("refuses an unknown key, an empty group and a bad permission", () => {
    expect(() =>
      resolve({ a: { columns: ["budget"], update: "p.a", extra: 1 } }),
    ).toThrow('unknown key "extra"');
    expect(() => resolve({ a: { columns: [], update: "p.a" } })).toThrow(
      "tables.projects.columnGroups.a",
    );
    expect(() =>
      resolve({ a: { columns: ["budget"], update: "not a key" } }),
    ).toThrow("tables.projects.columnGroups.a");
  });

  it("names the groups that list a column", () => {
    const groups = { money: { columns: ["budget"], update: "p.m" } };

    expect(groupsOfColumn(groups, "budget")).toEqual(["money"]);
    expect(groupsOfColumn(groups, "rate")).toEqual([]);
    expect(groupsOfColumn(undefined, "rate")).toEqual([]);
  });
});

describe("appTables columnGroups errors", () => {
  it("refuses malformed groups", () => {
    expect(() => resolve("x")).toThrow("must be an object keyed by group name");
    expect(() => resolve({})).toThrow("1 to");
    expect(() =>
      resolve({ Bad: { columns: ["budget"], update: "projects.budget" } }),
    ).toThrow("not a group name");
    expect(() => resolve({ money: "x" })).toThrow("must be an object with");
    expect(() =>
      resolve({
        money: { columns: ["budget"], update: "projects.budget", extra: 1 },
      }),
    ).toThrow("unknown key");
    expect(() =>
      resolve({ money: { columns: [], update: "projects.budget" } }),
    ).toThrow("list of column names");
    expect(() =>
      resolve({
        a: { columns: ["budget"], update: "projects.budget" },
        b: { columns: ["budget"], update: "projects.rate" },
      }),
    ).toThrow("belongs to one group");
    expect(() =>
      resolve({ money: { columns: ["budget"], update: "no way" } }),
    ).toThrow("permission key");
  });
});
