import { describe, expect, it } from "vitest";

import { DIFF_LINES, fileDiff } from "../../src/cli/diff.ts";
import {
  colorEnabled,
  highlight,
  painter,
  plain,
} from "../../src/cli/style.ts";

const tag = painter(true);

describe("painter", () => {
  it("colors only when asked", () => {
    expect(painter(undefined)("red", "x")).toBe("x");
    expect(painter(false)).toBe(plain);
    expect(tag("red", "x")).toBe("\u001B[31mx\u001B[39m");
    expect(typeof colorEnabled()).toBe("boolean");
  });

  it("highlights the verbs that start lines", () => {
    expect(
      highlight("Wrote a\nWould write b\nKept    c (exists)\nother", tag),
    ).toBe(
      [
        `${tag("green", "Wrote")} a`,
        `${tag("yellow", "Would write")} b`,
        `${tag("dim", "Kept")}    c (exists)`,
        "other",
      ].join("\n"),
    );
    expect(highlight("Wrote a", plain)).toBe("Wrote a");
  });
});

describe("fileDiff", () => {
  it("shows a unified diff from the file on disk", () => {
    expect(fileDiff("a.ts", "one\ntwo\n", "one\nthree\n")).toBe(
      [
        "--- a.ts\ton disk",
        "+++ a.ts\tgenerated",
        "@@ -1,2 +1,2 @@",
        " one",
        "-two",
        "+three",
      ].join("\n"),
    );
  });

  it("diffs a missing file against nothing and colors the lines", () => {
    const diff = fileDiff("b.ts", undefined, "new\n", tag);
    expect(diff).toContain(tag("bold", "--- b.ts\tmissing"));
    expect(diff).toContain(tag("cyan", "@@ -0,0 +1,1 @@"));
    expect(diff).toContain(tag("green", "+new"));
    expect(fileDiff("b.ts", "old\n", "", tag)).toContain(tag("red", "-old"));
  });

  it("caps each file at DIFF_LINES", () => {
    const next = Array.from({ length: 100 }, (_, index) => `line ${index}`);
    const lines = fileDiff("c.ts", "", `${next.join("\n")}\n`).split("\n");
    expect(lines).toHaveLength(DIFF_LINES + 1);
    expect(lines.at(-1)).toBe(`... ${103 - DIFF_LINES} more diff lines`);
  });
});
