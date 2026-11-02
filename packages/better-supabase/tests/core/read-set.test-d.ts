import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";
import type { RecordSummaryRead } from "../../src/core/spec.ts";

import { blockRead } from "../../src/core/block-reads.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;

const betterSupabase = defineSupabase(schema);
const db = betterSupabase.connect(client);

const chrome = defineReadSet(
  betterSupabase,
  "app_chrome",
  { params: { organizationId: "uuid", kinds: "text[]", limit: "int4" } },
  (s, p) => {
    expectTypeOf(p.organizationId).toEqualTypeOf<string>();
    expectTypeOf(p.kinds).toEqualTypeOf<readonly string[]>();
    expectTypeOf(p.limit).toEqualTypeOf<number>();

    return {
      names: s.customers.list({
        select: ["id", "name"],
        where: { organizationId: p.organizationId },
      }),
      calls: s.notes.count({ where: { organizationId: p.organizationId } }),
    };
  },
);

const mine = defineReadSet(betterSupabase, "mine", {}, (s, _p, auth) => {
  expectTypeOf(auth.uid).toEqualTypeOf<string>();

  return { mine: s.customers.count({ where: { createdBy: auth.uid } }) };
});

describe("db.$many", () => {
  it("types a read set result by key", () => {
    expectTypeOf(
      db.$many(chrome, { organizationId: "o", kinds: ["call"], limit: 5 }),
    ).toEqualTypeOf<
      AsyncResult<{
        readonly names: { id: string; name: string }[];
        readonly calls: number;
      }>
    >();
  });

  it("requires every parameter with its type", () => {
    // @ts-expect-error kinds is missing
    void db.$many(chrome, { organizationId: "o", limit: 5 });
    // @ts-expect-error limit is a number
    void db.$many(chrome, { organizationId: "o", kinds: [], limit: "5" });
  });

  it("runs a set that reads auth.uid with no parameters", () => {
    expectTypeOf(db.$many(mine, {})).toEqualTypeOf<
      AsyncResult<{ readonly mine: number }>
    >();
  });

  it("returns a tuple for ad-hoc specs", () => {
    expectTypeOf(
      db.$many([
        betterSupabase.spec.tags.count(),
        betterSupabase.spec.customers.list({ select: ["id"], limit: 1 }),
      ]),
    ).toEqualTypeOf<AsyncResult<[number, { id: string }[]]>>();
  });
});

describe("function reads", () => {
  it("type each entry as the function's result", async () => {
    const withFunctions = defineReadSet(
      betterSupabase,
      "with_functions",
      {},
      (s) => ({
        total: s.customers.count(),
        counts: s.$fn.customer_note_counts({ p_customer_ids: ["c1"] }),
      }),
    );

    const result = await db.$many(withFunctions, {}).orThrow();

    expectTypeOf(result.total).toEqualTypeOf<number>();
    expectTypeOf(result.counts).not.toBeAny();
  });
});

describe("block reads in a read set", () => {
  it("types the arguments and the result of a block read", () => {
    const set = defineReadSet(
      betterSupabase,
      "typed_block_reads",
      {
        params: { status: "text" },
        blocks: {
          customers: {
            byStatus: blockRead<{ status: string }, { readonly total: number }>(
              "customers_by_status",
              { status: "p_status" },
            ),
          },
        },
      },
      (s, p) => ({
        byStatus: s.blocks.customers.byStatus({ status: p.status }),
        header: s.record("customer", "c1"),
      }),
    );

    expectTypeOf(db.$many(set, { status: "x" })).toEqualTypeOf<
      AsyncResult<{
        readonly byStatus: { readonly total: number };
        readonly header: RecordSummaryRead | null;
      }>
    >();
  });
});
