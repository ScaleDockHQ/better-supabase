import { describe, expect, it } from "vitest";

import { defineSimpleList } from "@/lib/simple-list";

const list = defineSimpleList({
  facets: ["status"],
  sorts: ["name", "recent"],
  defaultSort: "recent",
});

describe("simple list", () => {
  it("falls back to the default sort", () => {
    const parsed = list.parse(new URLSearchParams("sort=bogus"));

    expect(parsed).toEqual({ ok: true, value: { sort: "recent", facets: {} } });
  });

  it("round-trips search, sort, cursor and facets", () => {
    const parsed = list.parse(
      new URLSearchParams("q=hi&sort=name&after=9&status=a,b"),
    );

    const value = parsed.ok ? parsed.value : { sort: "", facets: {} };

    expect(parsed.ok).toBe(true);
    expect(value.facets).toEqual({ status: ["a", "b"] });
    expect(list.toSearchParams(value).toString()).toBe(
      "q=hi&sort=name&after=9&status=a%2Cb",
    );
  });

  it("leaves the default sort out of the URL", () => {
    expect(list.toSearchParams({ sort: "recent", facets: {} }).toString()).toBe(
      "",
    );
  });
});
