import { describe, expect, it } from "vitest";

import { postgresCacheNames } from "../../src/cache-postgres/names.ts";

describe("postgresCacheNames", () => {
  it("names the tables and functions from the defaults or the options", () => {
    expect(postgresCacheNames()).toEqual({
      schema: "public",
      entriesTable: "bsb_cache_entries",
      tagsTable: "bsb_cache_tags",
      getFunction: "bsb_cache_get",
      markTagsFunction: "bsb_cache_mark_tags",
    });
    expect(
      postgresCacheNames({ schema: "cache", functionPrefix: "pages" }),
    ).toMatchObject({
      schema: "cache",
      getFunction: "pages_get",
      markTagsFunction: "pages_mark_tags",
    });
  });
});
