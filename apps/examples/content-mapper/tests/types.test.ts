import { describe, expect, expectTypeOf, it } from "vitest";

import type { Models, RowOf } from "../src/lib/supabase/index.ts";

import {
  customersStatusValues,
  schema,
} from "../src/lib/supabase/generated.ts";

describe("content mapper example", () => {
  it("loads the runtime values without the mapper", () => {
    expect(customersStatusValues).toEqual(["lead", "active", "archived"]);
    expect(Object.keys(schema.meta.tables)).toContain("customers");
  });

  it("types the rows from schema.bsb", () => {
    expectTypeOf<RowOf<"customers">["status"]>().toEqualTypeOf<
      "lead" | "active" | "archived"
    >();
    expectTypeOf<keyof Models>().toExtend<string>();
  });
});
