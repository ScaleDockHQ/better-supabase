import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";

import { sha256Hex } from "../../src/sql/sha256.ts";

const node = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

describe("sha256Hex", () => {
  it("hashes the empty string and the standard test vector", () => {
    expect(sha256Hex("")).toBe(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    );
    expect(sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  it("matches node:crypto across block boundaries and for UTF-8 text", () => {
    for (const text of [
      "a".repeat(55),
      "a".repeat(56),
      "a".repeat(64),
      "b".repeat(1000),
      "create table é ✓ 🚀;\n",
    ]) {
      expect(sha256Hex(text)).toBe(node(text));
    }
  });
});
