import { describe, expect, it } from "vitest";

import { canonicalJson } from "../../src/core/canonical-json.ts";

describe("canonicalJson", () => {
  it("writes the same text whatever the key order", () => {
    expect(canonicalJson({ b: 1, a: { d: 2, c: [{ z: 1, y: 2 }] } })).toBe(
      '{"a":{"c":[{"y":2,"z":1}],"d":2},"b":1}',
    );

    expect(canonicalJson({ a: 1, b: 2 })).toBe('{"a":1,"b":2}');
  });

  it("keeps integer-like keys in the order JavaScript enumerates them", () => {
    expect(canonicalJson({ 10: "a", 9: "b" })).toBe('{"9":"b","10":"a"}');
  });
});
