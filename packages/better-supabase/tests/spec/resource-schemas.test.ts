import { describe, expect, it } from "vitest";

import {
  pageInputSchema,
  pageQuery,
  pageSchema,
} from "../../src/spec/resource-schemas.ts";

describe("resource schemas", () => {
  it("names after for cursors and page for offsets, plus size", () => {
    expect(pageQuery(true, 20).map((p) => p.name)).toEqual(["after", "size"]);
    expect(pageQuery(false, 20).map((p) => p.name)).toEqual(["page", "size"]);
  });

  it("builds the list input from the same parameters", () => {
    expect(pageInputSchema(true, 20)).toMatchObject({
      properties: { size: { maximum: 20 } },
      additionalProperties: false,
    });
  });

  it("describes the page counts of an offset page", () => {
    const schema = pageSchema({ type: "object" }, false);
    expect(JSON.stringify(schema)).toContain('"pages"');
  });
});
