import { describe, expect, it } from "vitest";

import { compileSql } from "../../src/compile/sql.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { vectorLiteral } from "../../src/core/search.ts";
import { IrBuilder } from "../../src/ir/build.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

describe("db.$search", () => {
  it("POSTs to search_<table> and filters and renames the rows", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: "n1", customerId: "c1" }],
    }));
    const rows = await betterSupabase
      .connect(client)
      .$search("notes", {
        vector: [0.1, 0.2],
        k: 3,
        select: ["id", "customerId"],
        where: { customerId: "c1" },
      })
      .orThrow();
    expect(rows).toEqual([{ id: "n1", customerId: "c1" }]);
    const request = last();
    expect(request.method).toBe("POST");
    expect(request.path).toBe("/rest/v1/rpc/search_notes");
    expect(request.body).toEqual({ query: "[0.1,0.2]", k: 3 });
    expect(request.params.get("select")).toBe("id,customerId:customer_id");
    expect(request.params.get("customer_id")).toBe("eq.c1");
    expect(request.params.get("limit")).toBe("3");
  });

  it("reads from the function in SQL", () => {
    const table = schema.meta.tables["notes"]!;
    const plan = compileSql({
      kind: "select",
      table,
      selection: new IrBuilder(schema.meta).selection(table, ["id"], undefined),
      where: undefined,
      orderBy: [],
      limit: 2,
      offset: undefined,
      count: undefined,
      head: false,
      single: undefined,
      source: {
        schema: "public",
        name: "search_notes",
        args: { query: "[1,0]", k: 2 },
      },
    });
    expect(plan.rows?.text).toContain(
      'from "public"."search_notes"("query" => $1, "k" => $2) as t0',
    );
    expect(plan.rows?.params.slice(0, 2)).toEqual(["[1,0]", 2]);
  });

  it("rejects bad input and executors without function sources", async () => {
    const { client } = capturingClient();
    const db = betterSupabase.connect(client);
    const empty = await db.$search("notes", { vector: [] });
    expect(empty.error?.kind).toBe("invalid_input");
    const zero = await db.$search("notes", { vector: [1], k: 0 });
    expect(zero.error?.kind).toBe("invalid_input");

    const plain = betterSupabase.connect({
      name: "custom",
      execute: () => Promise.resolve(ok({ rows: [], count: null })),
    });
    const unsupported = await plain.$search("notes", { vector: [1] });
    expect(unsupported.error).toMatchObject({
      kind: "invalid_request",
      message: expect.stringContaining("custom executor"),
    });
  });

  it("formats vectors as pgvector text", () => {
    expect(vectorLiteral([1, 0.5, -2])).toBe("[1,0.5,-2]");
    expect(vectorLiteral(" [1,2] ")).toBe("[1,2]");
    expect(vectorLiteral([Number.NaN])).toBeUndefined();
    expect(vectorLiteral("1,2")).toBeUndefined();
  });
});
