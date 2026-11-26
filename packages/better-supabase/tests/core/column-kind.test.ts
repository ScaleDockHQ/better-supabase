import { describe, expect, it } from "vitest";

import type { ColumnMeta } from "../../src/schema/types.ts";

import {
  columnField,
  columnKind,
  unmappedType,
} from "../../src/core/column-kind.ts";

const column = (type: string, extra: Partial<ColumnMeta> = {}): ColumnMeta => ({
  db: "c",
  type,
  ...extra,
});

describe("columnKind", () => {
  it("keeps text-like types as strings", () => {
    for (const type of [
      "text",
      "citext",
      "vector",
      "inet",
      "int4range",
      "bytea",
    ]) {
      expect(columnKind(column(type))).toEqual({ kind: "string" });
    }
  });

  it("maps geometry and geography to json", () => {
    expect(columnKind(column("geometry"))).toEqual({ kind: "json" });
    expect(columnKind(column("geography"))).toEqual({ kind: "json" });
  });

  it("leaves an unrecognized type unknown, and record and void too", () => {
    expect(columnKind(column("widget"))).toEqual({ kind: "unknown" });
    expect(columnKind(column("record"))).toEqual({ kind: "unknown" });
    expect(columnKind(column("void"))).toEqual({ kind: "unknown" });
    expect(unmappedType("widget")).toBe(true);
    expect(unmappedType("record")).toBe(false);
    expect(unmappedType("void")).toBe(false);
    expect(unmappedType("text")).toBe(false);
  });

  it("lets a codec win over the type", () => {
    expect(columnKind(column("int8", { codec: "bigint" }))).toEqual({
      kind: "bigint",
    });
    expect(columnKind(column("timestamptz", { codec: "instant" }))).toEqual({
      kind: "instant",
    });
  });
});

describe("columnField", () => {
  it("nests composite attributes and keeps domain bounds", () => {
    expect(
      columnField(
        column("address", {
          nullable: true,
          minimum: 0,
          fields: { city: column("text", { nullable: true }) },
        }),
      ),
    ).toEqual({
      kind: "object",
      fields: { city: { kind: "string", nullable: true } },
      nullable: true,
      minimum: 0,
    });
  });
});
