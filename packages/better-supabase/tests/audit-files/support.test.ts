import { describe, expect, it } from "vitest";

import {
  formatAmount,
  parseAmount,
  parseDate,
  sides,
} from "../../src/audit-files/support.ts";

describe("parseAmount", () => {
  it("reads signed decimals as minor units", () => {
    expect(parseAmount("12.5", undefined, "x")).toBe(1250n);
    expect(parseAmount("-0.07", 2, "x")).toBe(-7n);
    expect(parseAmount("+3", 2, "x")).toBe(300n);
    expect(parseAmount("1.230", 2, "x")).toBe(123n);
    expect(parseAmount("5", 0, "x")).toBe(5n);
    expect(parseAmount("0.001", 3, "x")).toBe(1n);
  });

  it("refuses text and lost digits", () => {
    expect(() => parseAmount("1e3", 2, "line")).toThrow(/line/);
    expect(() => parseAmount("1.234", 2, "line")).toThrow(/more than 2/);
  });
});

describe("formatAmount", () => {
  it("writes minor units with the scale", () => {
    expect(formatAmount(1250n, undefined)).toBe("12.50");
    expect(formatAmount(-7n, 2)).toBe("-0.07");
    expect(formatAmount(5n, 0)).toBe("5");
    expect(formatAmount(0n, 2)).toBe("0.00");
  });
});

describe("parseDate", () => {
  it("keeps the date of a date-time", () => {
    expect(parseDate("2026-02-28T10:00:00", "x")).toBe("2026-02-28");
  });

  it("refuses text and impossible dates", () => {
    expect(() => parseDate("soon", "d")).toThrow(/not a date/);
    expect(() => parseDate("2026-02-30", "d")).toThrow(/calendar date/);
  });
});

describe("sides", () => {
  it("splits a signed amount into a debit and a credit", () => {
    expect(sides(5n, "debit")).toEqual({ debit: 5n, credit: 0n });
    expect(sides(5n, "credit")).toEqual({ debit: 0n, credit: 5n });
    expect(sides(-5n, "debit")).toEqual({ debit: 0n, credit: 5n });
    expect(sides(-5n, "credit")).toEqual({ debit: 5n, credit: 0n });
  });
});
