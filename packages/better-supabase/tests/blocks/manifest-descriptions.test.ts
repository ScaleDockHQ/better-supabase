import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";

describe("block manifests", () => {
  it("state what each block does, in a sentence", () => {
    const missing = BLOCK_MANIFESTS.filter(
      (block) => !block.description.endsWith("."),
    ).map((block) => block.name);

    expect(missing).toEqual([]);
  });
});
