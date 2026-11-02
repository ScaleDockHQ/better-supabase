import { describe, expect, it } from "vitest";

import { sha256Hex } from "../../src/core/sha256.ts";

describe("sha256Hex", () => {
  it("hashes text to lowercase hex", async () => {
    expect(await sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });
});
