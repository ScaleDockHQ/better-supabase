import { describe, expectTypeOf, it } from "vitest";

import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../src/core/block-helpers.ts";

describe("the list contract types", () => {
  it("takes array filters and a keyset cursor", () => {
    expectTypeOf<PageOptions["filters"]>().toEqualTypeOf<
      Readonly<Record<string, readonly string[]>> | undefined
    >();
    expectTypeOf<PageOptions["after"]>().toEqualTypeOf<
      readonly string[] | undefined
    >();
  });

  it("counts with an exactness flag", () => {
    expectTypeOf<Count>().toEqualTypeOf<{
      readonly value: number;
      readonly exact: boolean;
    }>();
  });

  it("returns facet values with counts", () => {
    expectTypeOf<
      FacetResult["values"][number]["count"]
    >().toEqualTypeOf<Count>();
  });

  it("keeps the page shape", () => {
    expectTypeOf<ListPage<string>["items"]>().toEqualTypeOf<
      readonly string[]
    >();
  });
});
