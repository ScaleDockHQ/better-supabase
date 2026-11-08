import { describe, expect, it } from "vitest";

import { rangeChecks } from "../../../src/sql/emit/check.ts";

describe("rangeChecks", () => {
  it("writes a range inside a check as two comparisons", () => {
    expect(
      rangeChecks(
        "token text check (length(token) between 1 and 4096), n int check (n between 0 and total)",
      ),
    ).toBe(
      "token text check (length(token) >= 1 and length(token) <= 4096), n int check (n >= 0 and n <= total)",
    );
  });

  it("covers a range inside a larger and", () => {
    expect(rangeChecks('check (a > 0 and "b" between 1 and 5 or c)')).toBe(
      'check (a > 0 and "b" >= 1 and "b" <= 5 or c)',
    );
  });

  it("leaves not between, other operands and SQL outside a check alone", () => {
    const sql = [
      "check (n not between 1 and 2)",
      "check (a + b between 1 and 2)",
      "select x between 1 and 2;",
      "if y not between 0 and 720 then",
    ].join("\n");

    expect(rangeChecks(sql)).toBe(sql);
  });

  it("handles nested parentheses and an unclosed check", () => {
    expect(rangeChecks("check ((x between 1 and 2) and y)")).toBe(
      "check ((x >= 1 and x <= 2) and y)",
    );

    expect(rangeChecks("check (x between 1 and 2")).toBe(
      "check (x between 1 and 2",
    );
  });
});
