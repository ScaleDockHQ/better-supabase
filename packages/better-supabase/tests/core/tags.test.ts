import { describe, expect, it, vi } from "vitest";

import { cacheTagsOf, tagCache, tagFor } from "../../src/core/tags.ts";

describe("tagFor", () => {
  it("names table, row and tenant tags", () => {
    expect(tagFor("notes")).toBe("bsb:notes");
    expect(tagFor("notes", 7)).toBe("bsb:notes:7");
    expect(tagFor("notes", undefined, { tenant: "acme" })).toBe(
      "bsb:notes@acme",
    );
  });
});

describe("cacheTagsOf", () => {
  it("covers every table, the tenant and each changed row", () => {
    expect(
      cacheTagsOf({
        table: "notes",
        tables: ["notes", "projects"],
        ids: ["a"],
        tenant: "acme",
      }),
    ).toEqual([
      "bsb:notes",
      "bsb:notes@acme",
      "bsb:projects",
      "bsb:projects@acme",
      "bsb:notes:a",
    ]);
    expect(cacheTagsOf({ table: "notes", tables: ["notes"], ids: [] })).toEqual(
      ["bsb:notes", "bsb:notes@*"],
    );
  });
});

describe("tagCache", () => {
  it("hands the tags to invalidate", async () => {
    const invalidate = vi.fn();
    const adapter = tagCache(invalidate, "cdn");
    expect(adapter.name).toBe("cdn");
    await adapter.invalidate({ table: "notes", tables: ["notes"], ids: ["1"] });
    expect(invalidate).toHaveBeenCalledWith([
      "bsb:notes",
      "bsb:notes@*",
      "bsb:notes:1",
    ]);
  });
});
