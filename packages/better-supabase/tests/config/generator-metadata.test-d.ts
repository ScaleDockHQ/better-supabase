import type * as Typegen from "@supabase/postgrest-typegen";

import { describe, expectTypeOf, it } from "vitest";

import type {
  GeneratorMetadata,
  PostgresColumn,
  PostgresFunction,
} from "../../src/config/index.ts";

describe("the vendored GeneratorMetadata", () => {
  it("matches the pinned postgrest-typegen contract", () => {
    expectTypeOf<GeneratorMetadata>().toEqualTypeOf<Typegen.GeneratorMetadata>();
    expectTypeOf<PostgresColumn>().toEqualTypeOf<Typegen.PostgresColumn>();
    expectTypeOf<PostgresFunction>().toEqualTypeOf<Typegen.PostgresFunction>();
  });
});
