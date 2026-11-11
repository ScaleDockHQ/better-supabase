import { describe, expect, it } from "vitest";

import { parseStubs, runInput } from "@/features/workflows/builder/run-input";

describe("run input", () => {
  it("uses a JSON object as the input", () => {
    expect(runInput('{"items": ["a"]}')).toEqual({ items: ["a"] });
  });

  it("wraps plain text as input.text", () => {
    expect(runInput("hello")).toEqual({ text: "hello" });
  });

  it("treats broken JSON as text", () => {
    expect(runInput("{oops")).toEqual({ text: "{oops" });
  });

  it("reads no stubs from empty text", () => {
    expect(parseStubs("  ")).toEqual({ ok: true, stubs: {} });
  });
});
