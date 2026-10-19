import { describe, expectTypeOf, it } from "vitest";

import type { ParityPaths } from "../../src/cli/type-parity.ts";

describe("ParityPaths", () => {
  it("is never for the same shape, ignoring readonly and undefined", () => {
    expectTypeOf<
      ParityPaths<
        { a?: string | undefined; b: string[] },
        { readonly a?: string; readonly b: readonly string[] }
      >
    >().toEqualTypeOf<never>();
  });

  it("names keys only one side has and optional keys that differ", () => {
    expectTypeOf<
      ParityPaths<{ a: { b?: string; c: number } }, { a: { b: string } }>
    >().toEqualTypeOf<
      "a.c (only in the schema)" | "a (optional keys differ)"
    >();
  });

  it("names leaves and union members that differ", () => {
    expectTypeOf<
      ParityPaths<
        { a: string; u: string | { x: number } },
        { a: "one"; u: string | { x: string } }
      >
    >().toEqualTypeOf<"a" | "u">();
  });

  it("walks records and arrays", () => {
    expectTypeOf<
      ParityPaths<
        { r: Record<string, { n: number }[]> },
        { r: Record<string, { n: string }[]> }
      >
    >().toEqualTypeOf<`r.${string}[].n`>();
  });
});
