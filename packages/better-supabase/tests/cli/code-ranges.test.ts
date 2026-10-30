import { describe, expect, it } from "vitest";

import { codeRanges } from "../../src/cli/code-ranges.ts";

describe("codeRanges", () => {
  it("leaves out strings, template literals and comments", () => {
    const text = `a "b\\"c" d 'e' \`f\` // g\nh /* i */ j`;
    expect(
      codeRanges(text)
        .map(([start, end]) => text.slice(start, end))
        .join("|"),
    ).toBe(`a | d | | |\nh | j`);
  });

  it("ends an unterminated string at the end of its line", () => {
    const text = `a "b\nc`;
    expect(codeRanges(text).map(([s, e]) => text.slice(s, e))).toEqual([
      "a ",
      "\nc",
    ]);
  });

  it("ends an unterminated block comment at the end of the text", () => {
    const text = "a /* b\nc";
    expect(codeRanges(text).map(([s, e]) => text.slice(s, e))).toEqual(["a "]);
  });
});
