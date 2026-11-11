import { describe, expect, it, vi } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  SEARCH_KEY_RULES,
  searchKeyMismatches,
  searchKeyPairs,
} from "../../../src/cli/doctor/search-keys.ts";

const searched = {
  order: {
    table: "public.orders",
    search: { from: { view: "public.order_search", key: "order_id" } },
  },
};

const context = (
  database: DoctorContext["database"],
  subjects: Record<string, unknown> = searched,
): DoctorContext =>
  // SAFETY: BS632 reads only config.recordTypes and database.
  ({
    config: { subjects },
    ...(database === undefined ? {} : { database }),
  }) as unknown as DoctorContext;

const rule = SEARCH_KEY_RULES[0];

const live = (rows: Record<string, unknown>[]) => {
  const query = vi.fn<(sql: string) => Promise<Record<string, unknown>[]>>(() =>
    Promise.resolve(rows),
  );

  const database: LiveDatabase = {
    describe: "test database",
    session: true,
    // SAFETY: the rows hold the columns the query selects.
    query: query as LiveDatabase["query"],
  };

  return { database, query };
};

describe("search key types (BS632)", () => {
  it("pairs a source view and a watch with the record", () => {
    const pairs = searchKeyPairs({
      order: {
        table: "public.orders",
        idType: "uuid",
        search: {
          from: { view: "public.order_search", key: "order_id" },
          watch: [{ table: "public.customers", key: "id", via: "customer_id" }],
        },
      },
    });

    expect(pairs.map((pair) => pair.where)).toEqual([
      "order search.from",
      "order watch[0]",
    ]);
    expect(pairs[0]?.left).toEqual({
      schema: "public",
      table: "order_search",
      column: "order_id",
    });
    expect(pairs[1]?.right.column).toBe("customer_id");
  });

  it("reports a pair whose catalog types differ and skips an unknown column", () => {
    const pairs = searchKeyPairs({
      order: {
        table: "public.orders",
        search: { from: { view: "public.order_search", key: "order_id" } },
      },
    });

    expect(
      searchKeyMismatches(pairs, [
        {
          schema: "public",
          table: "order_search",
          column: "order_id",
          type: "text",
        },
        { schema: "public", table: "orders", column: "id", type: "uuid" },
      ]).map((pair) => pair.where),
    ).toEqual(["order search.from"]);

    expect(
      searchKeyMismatches(pairs, [
        { schema: "public", table: "orders", column: "id", type: "uuid" },
      ]),
    ).toEqual([]);
  });
});

describe("BS632 check", () => {
  it("skips without a live database", async () => {
    expect(await rule?.check(context(undefined))).toEqual([]);
    expect(await rule?.check(context({ skipped: "snapshot" }))).toEqual([]);
  });

  it("asks the catalog for the compared tables only and reports a mismatch", async () => {
    const { database, query } = live([
      {
        schema: "public",
        table: "order_search",
        column: "order_id",
        type: "text",
      },
      { schema: "public", table: "orders", column: "id", type: "uuid" },
    ]);

    const findings = await rule?.check(context(database));

    expect(findings).toHaveLength(1);
    expect(findings?.[0]?.target).toBe("public.order_search.order_id");
    expect(findings?.[0]?.message).toContain(
      '"public"."order_search"."order_id" and "public"."orders"."id"',
    );
    expect(query.mock.calls[0]?.[0]).toContain(
      "('public', 'order_search'), ('public', 'orders')",
    );
  });

  it("does not query when no subject has a search source", async () => {
    const { database, query } = live([]);

    expect(
      await rule?.check(
        context(database, { order: { table: "public.orders" } }),
      ),
    ).toEqual([]);
    expect(query).not.toHaveBeenCalled();
  });
});
