import { describe, expect, it } from "vitest";

import { generatorHash } from "../../../src/cli/sql/generator-hash.ts";

describe("generatorHash", () => {
  it("is one stable hex digest per process", async () => {
    const first = await generatorHash();

    expect(first).toMatch(/^[0-9a-f]{64}$/u);
    expect(await generatorHash()).toBe(first);
  });
});
