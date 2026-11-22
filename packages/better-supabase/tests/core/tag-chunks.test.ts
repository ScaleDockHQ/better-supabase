import { describe, expect, it } from "vitest";

import { MAX_TAGS_PER_CALL, chunkTags } from "../../src/core/tag-chunks.ts";

describe("chunkTags", () => {
  it("splits at 128 and keeps order", () => {
    const tags = Array.from({ length: 130 }, (_, index) => String(index));
    const chunks = chunkTags(tags);

    expect(MAX_TAGS_PER_CALL).toBe(128);
    expect(chunks.map((chunk) => chunk.length)).toEqual([128, 2]);
    expect(chunks.flat()).toEqual(tags);
  });

  it("returns no chunk for no tags", () => {
    expect(chunkTags([])).toEqual([]);
  });
});
