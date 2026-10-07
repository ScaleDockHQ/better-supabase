import { describe, expect, it } from "vitest";

import type { FunctionMeta, SchemaMeta } from "../../src/schema/types.ts";

import { decodeRpcResult, rpcFunction } from "../../src/core/rpc-result.ts";

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
