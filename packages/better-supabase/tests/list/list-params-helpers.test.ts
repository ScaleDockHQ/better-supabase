import { describe, expect, it } from "vitest";

import {
  MAX_FILTER_PARAM,
  UNSET,
  countsOf,
  facetSchema,
  filterParser,
} from "../../src/list/list-params.ts";

describe("countsOf", () => {
  it("starts every allowed value at zero and counts unset rows apart", () => {
    const facet = {
      key: "status",
      column: "status",
      nullable: true,
      values: ["open", "closed"],
    };

    expect(
      countsOf(facet, [
        { status: "open", _count: 3 },
        { status: null, _count: 2 },
        { status: undefined },
      ]),
    ).toEqual({ open: 3, closed: 0, [UNSET]: 2 });
    expect(countsOf({ key: "k", column: "k", nullable: false }, [])).toEqual(
      {},
    );
  });
});

describe("facetSchema", () => {
  it("lists the values and the unset marker only for a nullable enum", () => {
    expect(
      facetSchema({ key: "s", column: "s", nullable: true, values: ["a"] }),
    ).toMatchObject({ items: { type: "string", enum: ["a", UNSET] } });
    expect(
      facetSchema({ key: "s", column: "s", nullable: false, values: ["a"] }),
    ).toMatchObject({ items: { enum: ["a"] } });
    expect(
      facetSchema({ key: "s", column: "s", nullable: false }),
    ).toMatchObject({ items: { type: "string" } });
  });
});

describe("filterParser", () => {
  it("refuses an oversized, undecodable or non-group value", () => {
    expect(filterParser.parse("x".repeat(MAX_FILTER_PARAM + 1))).toBeNull();
    expect(filterParser.parse("not a filter")).toBeNull();
  });
});
