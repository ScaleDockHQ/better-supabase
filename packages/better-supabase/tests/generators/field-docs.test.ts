import { describe, expect, it } from "vitest";

import type { FieldPlan, TableDocs } from "../../src/generators/shared.ts";
import type { ColumnMeta } from "../../src/schema/types.ts";

import { fieldDocs, variantTitle } from "../../src/generators/shared.ts";

type Scalar = FieldPlan["scalar"];

function plan(
  scalar: Scalar,
  rest: Partial<FieldPlan> = {},
  array = false,
): FieldPlan {
  return {
    name: "value",
    // SAFETY: fieldDocs reads only db, array and storage from the column.
    column: { db: "value", array } as unknown as ColumnMeta,
    scalar,
    nullable: false,
    optional: false,
    customJson: false,
    managed: false,
    ...rest,
  };
}

const docs = (field: Record<string, unknown>): TableDocs => ({
  title: "Things",
  fields: new Map([["value", field]]),
});

const examplesFor = (
  scalar: Scalar,
  examples: unknown[],
  rest: Partial<FieldPlan> = {},
  array = false,
) => fieldDocs(docs({ examples }), plan(scalar, rest, array)).examples ?? [];

describe("fieldDocs examples", () => {
  it.each([
    [{ kind: "string" }, ["a", 1], ["a"]],
    [{ kind: "uuid" }, ["x", null], ["x"]],
    [
      { kind: "datetime" },
      ["2026-01-01T00:00:00Z", 5],
      ["2026-01-01T00:00:00Z"],
    ],
    [{ kind: "date" }, ["2026-01-01", true], ["2026-01-01"]],
    [{ kind: "enum", values: ["a", "b"] }, ["a", "c", 1], ["a"]],
    [{ kind: "integer" }, [1, 1.5, "1"], [1]],
    [{ kind: "number" }, [1.5, "1.5"], [1.5]],
    [{ kind: "boolean" }, [true, "true"], [true]],
    [{ kind: "json" }, [{ a: 1 }, "x"], [{ a: 1 }, "x"]],
    [{ kind: "unknown" }, [1], [1]],
    [{ kind: "instant" }, ["2026-01-01T00:00:00Z"], []],
    [{ kind: "plainDate" }, ["2026-01-01"], []],
    [{ kind: "plainDateTime" }, ["2026-01-01T00:00:00"], []],
    [{ kind: "bigint" }, [1], []],
  ] as [Scalar, unknown[], unknown[]][])(
    "keeps %o examples its type accepts",
    (scalar, given, kept) => {
      expect(examplesFor(scalar, given)).toEqual(kept);
    },
  );

  it("accepts null only for nullable fields and checks array items", () => {
    expect(examplesFor({ kind: "string" }, [null], { nullable: true })).toEqual(
      [null],
    );
    expect(examplesFor({ kind: "string" }, [null])).toEqual([]);
    expect(
      examplesFor({ kind: "string" }, [["a", "b"], ["a", 1], "a"], {}, true),
    ).toEqual([["a", "b"]]);
  });
});

describe("fieldDocs bounds", () => {
  const bounds = {
    description: "Amount",
    minimum: 1,
    exclusiveMinimum: 0,
    maximum: 9,
    exclusiveMaximum: 10,
    minLength: 2,
    maxLength: 5,
  };

  it("carries value bounds on numbers and length bounds on text", () => {
    expect(fieldDocs(docs(bounds), plan({ kind: "integer" }))).toEqual({
      description: "Amount",
      minimum: 1,
      exclusiveMinimum: 0,
      maximum: 9,
      exclusiveMaximum: 10,
    });
    expect(fieldDocs(docs(bounds), plan({ kind: "number" })).maximum).toBe(9);
    expect(fieldDocs(docs(bounds), plan({ kind: "string" }))).toEqual({
      description: "Amount",
      minLength: 2,
      maxLength: 5,
    });
    expect(fieldDocs(docs({ minimum: 1 }), plan({ kind: "integer" }))).toEqual({
      minimum: 1,
    });
  });

  it("drops bounds for arrays, other types and custom or stored columns", () => {
    expect(
      fieldDocs(docs(bounds), plan({ kind: "integer" }, {}, true)),
    ).toEqual({ description: "Amount" });
    expect(fieldDocs(docs(bounds), plan({ kind: "boolean" }))).toEqual({
      description: "Amount",
    });
    expect(
      fieldDocs(docs(bounds), plan({ kind: "string" }, { customJson: true })),
    ).toEqual({});
    expect(fieldDocs(undefined, plan({ kind: "string" }))).toEqual({});
    expect(
      fieldDocs({ title: "T", fields: new Map() }, plan({ kind: "string" })),
    ).toEqual({});

    const stored = plan({ kind: "string" });

    expect(
      fieldDocs(docs(bounds), {
        ...stored,
        // SAFETY: only the storage field is read from the column.
        column: { ...stored.column, storage: {} } as unknown as ColumnMeta,
      }),
    ).toEqual({});
  });
});

describe("variantTitle", () => {
  it("names the row and its write variants", () => {
    const table = docs({});

    expect(variantTitle(table, "Row")).toBe("Things");
    expect(variantTitle(table, "Insert")).toBe("Things insert");
    expect(variantTitle(table, "Update")).toBe("Things update");
  });
});
