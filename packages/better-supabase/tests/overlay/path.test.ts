import { describe, expect, it } from "vitest";

import {
  decodePointerToken,
  formatPath,
  parseNormalizedPath,
} from "../../src/overlay/path.ts";

describe("parseNormalizedPath", () => {
  it("parses names, indexes and every escape", () => {
    expect(parseNormalizedPath("$")).toEqual([]);
    expect(
      parseNormalizedPath(
        "$['paths']['/a/{id}'][0][12]['\\b\\f\\n\\r\\t\\'\\\\\\/\\u001f']",
      ),
    ).toEqual(["paths", "/a/{id}", 0, 12, "\b\f\n\r\t'\\/\u001F"]);
  });

  it.each([
    "a",
    "$.a",
    "$[01]",
    "$[-1]",
    "$['a'",
    "$['\\x']",
    "$[1",
    "$['a']x",
  ])("rejects %s", (path) => {
    expect(() => parseNormalizedPath(path)).toThrow("Not a normalized path");
  });
});

describe("formatPath", () => {
  it("uses shorthand for plain names and brackets otherwise", () => {
    expect(formatPath([])).toBe("$");
    expect(formatPath(["paths", "/customers", "get", 0, "x-a", "_ok1"])).toBe(
      "$.paths['/customers'].get[0]['x-a']._ok1",
    );
    expect(formatPath(["\b\f\r"])).toBe("$['\\b\\f\\r']");
  });
});

describe("decodePointerToken", () => {
  it("decodes ~1 before ~0", () => {
    expect(decodePointerToken("a~1b~0c~01")).toBe("a/b~c~1");
  });
});
