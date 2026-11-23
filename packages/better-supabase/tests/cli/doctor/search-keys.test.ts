import { describe, expect, it, vi } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  SEARCH_KEY_RULES,
  searchKeyMismatches,
  searchKeyPairs,
  searchViewSources,
  unlistedViewColumns,
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

describe("BS637 check", () => {
  const unlisted = SEARCH_KEY_RULES[1];

  const viewed = {
    order: {
      table: "public.orders",
      tenant: "tenant_id",
      search: {
        from: { view: "public.order_search", key: "order_id" },
        columns: ["number"],
      },
    },
  };

  const use = (table: string, column: string) => ({
    view_schema: "public",
    view_name: "order_search",
    table_schema: "public",
    table_name: table,
    column_name: column,
  });

  it("lists the record's own columns the view reads and the config leaves out", () => {
    expect(
      unlistedViewColumns(searchViewSources(viewed), [
        use("orders", "number"),
        use("orders", "id"),
        use("orders", "tenant_id"),
        use("orders", "title"),
        use("orders", "status"),
        use("customers", "name"),
      ]).map((entry) => entry.missing),
    ).toEqual([["status", "title"]]);
  });

  it("reads view_column_usage for the source views and reports the gap", async () => {
    const { database, query } = live([use("orders", "title")]);
    const findings = await unlisted?.check(context(database, viewed));

    expect(unlisted?.code).toBe("BS637");
    expect(findings).toHaveLength(1);
    expect(findings?.[0]?.target).toBe("order.search.columns");
    expect(findings?.[0]?.message).toContain(
      'reads "title" of "public"."orders"',
    );
    expect(query.mock.calls[0]?.[0]).toContain("view_column_usage");
    expect(query.mock.calls[0]?.[0]).toContain("('public', 'order_search')");
  });

  it("skips without a live database or a source view", async () => {
    expect(await unlisted?.check(context(undefined, viewed))).toEqual([]);

    const { database, query } = live([]);

    expect(
      await unlisted?.check(
        context(database, { order: { table: "public.orders" } }),
      ),
    ).toEqual([]);
    expect(query).not.toHaveBeenCalled();
  });
});
