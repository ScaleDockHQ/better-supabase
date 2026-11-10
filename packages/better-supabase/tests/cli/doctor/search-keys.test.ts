import { describe, expect, it } from "vitest";

import {
  searchKeyMismatches,
  searchKeyPairs,
} from "../../../src/cli/doctor/search-keys.ts";

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
