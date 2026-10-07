import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { InferResult } from "../../src/core/spec.ts";

import { defineSupabase } from "../../src/core/define.ts";
import {
  schema as camel,
  type CustomersStatus,
} from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const betterSupabase = defineSupabase(camel);
const db = betterSupabase.connect(client);

describe("aggregate types", () => {
  it("types relation aggregates next to the row", async () => {
    const rows = await db.customers
      .findMany({
        select: ["id"],
        include: {
          _sum: { notes: { id: true } },
          _max: { notes: { createdAt: true } },
          _count: { notes: true },
        },
      })
      .orThrow();
    expectTypeOf(rows).toEqualTypeOf<
      {
        id: string;
        _count: { notes: number };
        _sum: { notes: { id: number | null } };
        _max: { notes: { createdAt: string | null } };
      }[]
    >();
  });

  it("types grouped and single aggregates", async () => {
    const groups = await db.customers
      .aggregate({
        groupBy: ["status"],
        _count: true,
        _min: { createdAt: true },
      })
      .orThrow();
    expectTypeOf(groups).toEqualTypeOf<
      {
        status: CustomersStatus;
        _count: number;
        _min: { createdAt: string | null };
      }[]
    >();

    const total = await db.notes
      .aggregate({ _avg: { id: true }, _sum: { id: true } })
      .orThrow();
    expectTypeOf(total).toEqualTypeOf<{
      _avg: { id: number | null };
      _sum: { id: number | null };
    }>();
  });

  it("sorts groups by _count, measures and columns without changing the row", async () => {
    const groups = await db.notes
      .aggregate({
        groupBy: ["customerId"],
        _count: true,
        orderBy: [
          { _count: "desc" },
          { _sum: { id: { direction: "desc", nulls: "last" } } },
          { _max: { createdAt: "desc" } },
          { customerId: "asc" },
        ],
      })
      .orThrow();
    expectTypeOf(groups).toEqualTypeOf<
      { customerId: string; _count: number }[]
    >();
  });

  it("only sorts by sums and averages of numeric columns", () => {
    void db.customers.aggregate({
      _count: true,
      // @ts-expect-error jsonb is not numeric
      orderBy: { _avg: { metadata: "asc" } },
    });
    // @ts-expect-error a measure maps columns to a direction
    void db.notes.aggregate({ _count: true, orderBy: { _max: "desc" } });
    // @ts-expect-error _count takes a direction
    void db.notes.aggregate({ _count: true, orderBy: { _count: true } });
  });

  it("only sums numeric columns and only aggregates to-many relations", () => {
    // @ts-expect-error jsonb is not numeric
    void db.customers.aggregate({ _sum: { metadata: true } });
    void db.customers.findMany({
      // @ts-expect-error organization is to-one
      include: { _max: { organization: { name: true } } },
    });
  });

  it("infers spec results", () => {
    const spec = betterSupabase.spec.customers.aggregate({
      groupBy: ["status"],
      _count: true,
    });
    expectTypeOf<InferResult<typeof spec>>().toEqualTypeOf<
      { status: CustomersStatus; _count: number }[]
    >();
  });
});
