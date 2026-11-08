import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

const executor = {
  name: "none",
  execute: () => {
    throw new Error("not called");
  },
};

const db = createSupabase(schema).connect(executor);

const coded = createSupabase(
  defineSchema({
    ...schema.meta,
    tables: {
      ...schema.meta.tables,
      tags: {
        ...schema.meta.tables["tags"]!,
        columns: {
          ...schema.meta.tables["tags"]!.columns,
          createdAt: {
            ...schema.meta.tables["tags"]!.columns["createdAt"]!,
            codec: "instant",
          },
        },
      },
    },
  }),
).connect(executor);

describe("db.$decode", () => {
  it("renames database columns to the configured casing", () => {
    const result = db.$decode("tags").row({ id: "t1", created_at: "x" });

    expect(result.ok && result.data).toMatchObject({
      id: "t1",
      createdAt: "x",
    });
  });

  it("returns a validation error for a value that is not an object", () => {
    const result = db.$decode("tags").row(null);

    expect(!result.ok && result.error.kind).toBe("validation");
  });

  it("decodes a list and reports a value that is not a list", () => {
    const rows = db.$decode("tags").rows([{ id: "a" }, { id: "b" }]);

    expect(rows.ok && rows.data.map((row) => row.id)).toEqual(["a", "b"]);
    expect(db.$decode("tags").rows({}).ok).toBe(false);
  });

  it("throws for an unknown table", () => {
    // @ts-expect-error the table does not exist
    expect(() => db.$decode("nope")).toThrow(/unknown table/);
  });

  it("reports a value a column codec rejects instead of throwing", () => {
    const row = coded.$decode("tags").row({ id: "t1", created_at: "infinity" });

    expect(!row.ok && row.error.kind).toBe("invalid_value");
  });

  it("rethrows a failure that is not a database error", () => {
    expect(() =>
      coded.$decode("tags").row({ id: "t1", created_at: "nope" }),
    ).toThrow(RangeError);
  });

  it("stops a list at the first row that fails to decode", () => {
    const rows = coded.$decode("tags").rows([
      { id: "a", created_at: "2026-01-01T00:00:00Z" },
      { id: "b", created_at: "infinity" },
      { id: "c", created_at: "infinity" },
    ]);

    expect(!rows.ok && rows.error.kind).toBe("invalid_value");
  });

  it("decodes embedded relations at every depth", () => {
    const row = coded
      .$decode("customerTags")
      .row({
        customer_id: "c1",
        tag: { id: "t1", created_at: "2026-01-01T00:00:00Z" },
      });

    expect(row.ok && row.data).toMatchObject({
      customerId: "c1",
      tag: { id: "t1" },
    });
    expect(
      row.ok &&
        typeof (row.data as { tag: { createdAt: unknown } }).tag.createdAt,
    ).toBe("object");
  });

  it("reports an embedded row that fails to decode", () => {
    const row = coded
      .$decode("customerTags")
      .row({ customer_id: "c1", tag: { id: "t1", created_at: "infinity" } });

    expect(!row.ok && row.error.kind).toBe("invalid_value");
  });
});
