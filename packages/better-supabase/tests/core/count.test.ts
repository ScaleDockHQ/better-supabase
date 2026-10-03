import { describe, expect, it } from "vitest";

import { compileSql } from "../../src/compile/sql.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { IrBuilder } from "../../src/ir/build.ts";
import { decodeRows } from "../../src/ir/codec.ts";
import { capturingClient, query } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

describe("_count includes", () => {
  it("renders a count embed and folds it into row._count", async () => {
    const { client, last } = capturingClient(() => ({
      body: [
        {
          id: "c1",
          _count_notes: [{ count: 3 }],
          _count_locations: [{ count: 0 }],
        },
      ],
    }));
    const db = betterSupabase.connect(client);
    const rows = await db.customers
      .findMany({
        select: ["id"],
        include: {
          _count: { notes: true, locations: { where: { city: "Delft" } } },
        },
        limit: 10,
      })
      .orThrow();

    const params = query(last());
    expect(params[0]).toBe(
      "select=id,_count_notes:notes!notes_customer_id_fkey(count),_count_locations:locations!locations_customer_id_fkey(count)",
    );
    expect(params).toContain("_count_locations.city=eq.Delft");
    expect(rows).toEqual([{ id: "c1", _count: { notes: 3, locations: 0 } }]);
  });

  it("compiles to a count(*) subquery in SQL", () => {
    const builder = new IrBuilder(schema.meta);
    const table = builder.table("customers");
    const selection = builder.selection(table, ["id"], {
      _count: { notes: true },
    });
    const plan = compileSql({
      kind: "select",
      table,
      selection,
      where: undefined,
      orderBy: [],
      limit: undefined,
      offset: undefined,
      count: undefined,
      head: false,
      single: undefined,
    });
    expect(plan.rows?.text).toContain('(select count(*) from "public"."notes"');
    expect(decodeRows(selection, [{ id: "c1", _count_notes: "2" }])).toEqual([
      { id: "c1", _count: { notes: 2 } },
    ]);
  });

  it("rejects counts over to-one relations", async () => {
    const { client } = capturingClient();
    const result = await betterSupabase.connect(client).customers.findMany({
      include: { _count: { organization: true } as never },
    });
    expect(result.error?.message).toContain("needs a to-many relation");
  });
});
