import type { SupabaseClient } from "@supabase/supabase-js";

import { useQuery } from "@tanstack/react-query";
import { describe, expectTypeOf, it } from "vitest";

import type { BetterQueryMeta } from "../../src/query/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createQueries } from "../../src/query/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare module "@tanstack/query-core" {
  interface Register {
    queryMeta: { readonly toast?: string };
  }
}

declare const client: SupabaseClient;
const betterSupabase = defineSupabase(schema);
const q = createQueries(betterSupabase, betterSupabase.connect(client));

describe("query meta with a registered queryMeta", () => {
  it("keeps the app's meta fields next to bsTables", () => {
    expectTypeOf<BetterQueryMeta["toast"]>().toEqualTypeOf<
      string | undefined
    >();
    expectTypeOf<BetterQueryMeta["bsTables"]>().toEqualTypeOf<
      readonly string[]
    >();
    const options = q.customers.findMany({ select: ["id"] });
    useQuery({ ...options, meta: { ...options.meta, toast: "Loaded" } });
    useQuery(options);
  });
});
