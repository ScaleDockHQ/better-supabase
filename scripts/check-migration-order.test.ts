import { describe, expect, it } from "vitest";

import { outOfOrder } from "./check-migration-order.ts";

describe("outOfOrder", () => {
  const base = ["20260101000000_a.sql", "20260301000000_b.sql"];

  it("accepts migrations newer than main's newest", () => {
    expect(outOfOrder(base, ["20260401000000_c.sql"])).toEqual([]);
  });

  it("lists migrations older than main's newest", () => {
    expect(
      outOfOrder(base, ["20260201000000_c.sql", "20260401000000_d.sql"]),
    ).toEqual(["20260201000000_c.sql"]);
  });

  it("accepts anything when main has no migration", () => {
    expect(outOfOrder([], ["20260101000000_a.sql"])).toEqual([]);
  });
});
