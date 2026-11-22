import { describe, expect, it } from "vitest";

import { codeRanges } from "../../../src/cli/config-document/ranges.ts";

const code = (text: string): string =>
  codeRanges(text)
    .map(([start, end]) => text.slice(start, end))
    .join("|");

describe("codeRanges", () => {
  it("leaves out strings, template text and comments", () => {
    expect(code(`a("b\\"c", 'e', \`f\`); // g\nh(); /* i */ j();`)).toBe(
      `a(|, |, |); |\nh(); | j();`,
    );
  });

  it("keeps the expressions of a template literal as code", () => {
    const text = ["x = `a", "{b}c", "{`d", "{e}`}`;"].join("$");

    expect(code(text)).toBe("x = |b|e|;");
  });

  it("does not take a quote in a regular expression for a string", () => {
    expect(code(`const r = /"/; call();`)).toBe("const r = |; call();");
  });

  it("does not take JSX text for code", () => {
    expect(code(`const a = <p>it's "x"</p>; call();`)).toBe(
      "const a = <p>|</p>; call();",
    );
  });

  it("keeps the code of a file that does not parse", () => {
    expect(code(`call(); // x\nfoo(`)).toContain("call();");
  });

  it("reads a TypeScript generic arrow, which TSX cannot parse", () => {
    expect(
      code(`const f = <T,>(x: T) => x; // note, with a comma\ncall();`),
    ).toBe("const f = <T,>(x: T) => x; |\ncall();");
    expect(
      code(`const f = <V extends string = never>(x: V) => x; // a, b\ncall();`),
    ).toBe("const f = <V extends string = never>(x: V) => x; |\ncall();");
  });
});
