import { describe, expect, it } from "vitest";

import type { FunctionMeta, SchemaMeta } from "../../src/schema/types.ts";

import {
  decodeRpcResult,
  rpcFunction,
  rpcSelect,
} from "../../src/core/rpc-result.ts";

const base = { returnsSet: false, volatility: "stable" } as const;

const area: FunctionMeta = {
  name: "area",
  schema: "public",
  ...base,
  args: [],
  returns: "text",
  overloads: [
    { ...base, args: [], returns: "text" },
    {
      ...base,
      args: [
        { name: "label", type: "text" },
        { name: "scale", type: "int4", optional: true },
      ],
      returns: "record",
      returnsSet: true,
      result: { columns: [{ db: "item_label", name: "itemLabel" }] },
    },
    { ...base, args: [{ name: "side", type: "int4" }], returns: "int4" },
    { ...base, args: [{ name: "side", type: "text" }], returns: "text" },
    { ...base, args: [{ name: "w", type: "int4" }], returns: "int4" },
  ],
};

const meta: SchemaMeta = {
  version: 1,
  casing: "camel",
  tables: {},
  enums: {},
  functions: {
    area,
    ping: {
      name: "ping",
      schema: "public",
      ...base,
      args: [],
      returns: "void",
    },
  },
};

describe("rpcFunction", () => {
  it("returns a function with one signature as is", () => {
    expect(rpcFunction(meta, "ping", "public", { any: 1 })).toBe(
      meta.functions["ping"],
    );
  });

  it("returns nothing for another schema or an unknown name", () => {
    expect(rpcFunction(meta, "ping", "private", {})).toBeUndefined();
    expect(rpcFunction(meta, "nope", "public", {})).toBeUndefined();
  });

  it("picks the overload whose argument names match", () => {
    expect(rpcFunction(meta, "area", "public", {})).toMatchObject({
      name: "area",
      schema: "public",
      args: [],
    });
    const labelled = rpcFunction(meta, "area", "public", { label: "x" });
    expect(labelled).toMatchObject({ returnsSet: true, returns: "record" });
    expect(
      rpcFunction(meta, "area", "public", { label: "x", scale: undefined }),
    ).toBe(labelled);
    expect(rpcFunction(meta, "area", "public", { w: 1 })?.returns).toBe("int4");
  });

  it("returns nothing when no overload or more than one matches", () => {
    expect(rpcFunction(meta, "area", "public", { side: 1 })).toBeUndefined();
    expect(rpcFunction(meta, "area", "public", { scale: 1 })).toBeUndefined();
    expect(
      rpcFunction(meta, "area", "public", { label: "x", w: 1 }),
    ).toBeUndefined();
  });

  it("decodes with the picked overload", () => {
    const fn = rpcFunction(meta, "area", "public", { label: "x" });
    expect(decodeRpcResult(meta, fn, [{ item_label: "x" }])).toEqual([
      { itemLabel: "x" },
    ]);
    expect(decodeRpcResult(meta, undefined, [{ item_label: "x" }])).toEqual([
      { item_label: "x" },
    ]);
  });
});

describe("rpcSelect", () => {
  const totals: FunctionMeta = {
    name: "totals",
    schema: "public",
    ...base,
    args: [],
    returns: "record",
    returnsSet: true,
    result: {
      columns: [
        { db: "label", name: "label" },
        { db: "amount", name: "amount", codec: "bigint" },
      ],
    },
  };

  const deals: FunctionMeta = {
    name: "deals",
    schema: "public",
    ...base,
    args: [],
    returns: "setof deals",
    returnsSet: true,
    result: { table: "deals" },
  };

  const withTable: SchemaMeta = {
    ...meta,
    tables: {
      deals: {
        key: "deals",
        name: "deals",
        schema: "public",
        kind: "table",
        primaryKey: ["id"],
        uniqueKeys: {},
        relations: {},
        flags: {},
        columns: {
          id: { db: "id", type: "uuid", nullable: false, hasDefault: true },
          valueAmount: {
            db: "value_amount",
            type: "int8",
            nullable: false,
            hasDefault: false,
            codec: "bigint",
          },
        },
      },
    },
  };

  it("lists every result column and casts the ones with a codec", () => {
    expect(rpcSelect(meta, totals)).toEqual([
      { column: "label" },
      { column: "amount", cast: "text" },
    ]);
    expect(rpcSelect(withTable, deals)).toEqual([
      { column: "id" },
      { column: "value_amount", cast: "text" },
    ]);
  });

  it("returns nothing without a codec column, a result shape or a function", () => {
    const labelled = rpcFunction(meta, "area", "public", { label: "x" });

    expect(rpcSelect(meta, labelled)).toBeUndefined();
    expect(rpcSelect(meta, meta.functions["ping"])).toBeUndefined();
    expect(rpcSelect(meta, undefined)).toBeUndefined();
  });
});
