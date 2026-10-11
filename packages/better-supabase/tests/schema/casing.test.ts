import { describe, expect, it } from "vitest";

import type { TableMeta } from "../../src/schema/types.ts";

import { toApp, toDb } from "../../src/schema/casing.ts";

// SAFETY: the converters read `columns` only.
const table = {
  primaryKey: ["name"],
  uniqueKeys: {},
  columns: {
    createdAt: { db: "created_at" },
    name: { db: "name" },
  },
} as unknown as TableMeta;

describe("casing converters", () => {
  it("renames database keys to app keys and drops unknown ones", () => {
    expect(toApp(table, { created_at: 1, name: "a", extra: 2 })).toEqual({
      createdAt: 1,
      name: "a",
    });
  });

  it("renames app keys to database keys and drops unknown ones", () => {
    expect(toDb(table, { createdAt: 1, extra: 2 })).toEqual({ created_at: 1 });
  });
});
