import { describe, expect, it } from "vitest";

import { byFolder, outOfOrder } from "./check-migration-order.ts";

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

describe("byFolder", () => {
  it("groups the root and validation migrations and ignores other files", () => {
    expect(
      Object.fromEntries(
        byFolder([
          "supabase/migrations/20260101000000_a.sql",
          "supabase/migrations/nested/20260101000000_x.sql",
          "tests/validation-lienlink/supabase/migrations/20260201000000_b.sql",
          "tests/validation-lienlink/supabase/schemas/x.sql",
          "supabase/schemas/y.sql",
        ]),
      ),
    ).toEqual({
      "supabase/migrations/": ["20260101000000_a.sql"],
      "tests/validation-lienlink/supabase/migrations/": [
        "20260201000000_b.sql",
      ],
    });
  });
});
