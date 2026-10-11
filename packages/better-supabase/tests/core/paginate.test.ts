import { describe, expect, it } from "vitest";

import { offsetEnvelope, pageWindow, strip } from "../../src/core/paginate.ts";

describe("pageWindow", () => {
  it("reads page and size", () => {
    expect(pageWindow({ page: 3, size: 10 })).toEqual({ size: 10, offset: 20 });
  });
  it("reads limit and offset", () => {
    expect(pageWindow({ limit: 5, offset: 15 })).toEqual({
      size: 5,
      offset: 15,
    });
  });
  it("rejects mixed and invalid arguments", () => {
    expect(pageWindow({ limit: 5, size: 5 })).toHaveProperty("invalid");
    expect(pageWindow({ size: 0 })).toHaveProperty("invalid");
    expect(pageWindow({ size: 5, page: 0 })).toHaveProperty("invalid");
    expect(pageWindow({ limit: 5, offset: -1 })).toHaveProperty("invalid");
  });
});

describe("offsetEnvelope", () => {
  it("drops the look-ahead row and counts pages", () => {
    const out = offsetEnvelope([{ a: 1 }, { a: 2 }, { a: 3 }], 25, 2, 2);
    expect(out.items).toHaveLength(2);
    expect(out.page).toEqual({
      number: 2,
      size: 2,
      total: 25,
      pages: 13,
      hasMore: true,
    });
  });
  it("leaves pages unknown without a total", () => {
    expect(offsetEnvelope([], null, 5, 0).page).toMatchObject({
      pages: null,
      hasMore: false,
    });
  });
});

describe("strip", () => {
  it("removes the keys", () => {
    expect(strip({ a: 1, b: 2 }, ["b"])).toEqual({ a: 1 });
  });
});
