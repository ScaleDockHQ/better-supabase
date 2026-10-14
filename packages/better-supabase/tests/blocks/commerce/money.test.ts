import { describe, expect, it } from "vitest";

import {
  addMoney,
  allocateMoney,
  applyRate,
  compareMoney,
  CurrencyMismatchError,
  formatMoney,
  isCurrency,
  isMoney,
  isRate,
  minorUnits,
  money,
  moneyFromJson,
  moneyToJson,
  multiplyMoney,
  negateMoney,
  parseMoney,
  roundHalfEven,
  subtractMoney,
  sumMoney,
  toDecimal,
} from "../../../src/blocks/commerce/index.ts";

const eur = (amount: bigint) => money(amount, "EUR");

describe("money", () => {
  it("keeps a bigint of minor units and freezes the value", () => {
    const value = money(1999, "EUR");
    expect(value).toEqual({ amount: 1999n, currency: "EUR" });
    expect(Object.isFrozen(value)).toBe(true);
  });

  it("refuses an unknown currency and a fractional number", () => {
    expect(() => money(1n, "EURO")).toThrow(RangeError);
    expect(() => money(1n, "XAU")).toThrow(/ISO 4217/);
    expect(() => money(19.99, "EUR")).toThrow(/parseMoney/);
    expect(() => money(Number.MAX_SAFE_INTEGER + 1, "EUR")).toThrow(RangeError);
  });

  it("knows each currency's minor units", () => {
    expect(minorUnits("EUR")).toBe(2);
    expect(minorUnits("JPY")).toBe(0);
    expect(minorUnits("BHD")).toBe(3);
    expect(minorUnits("UYW")).toBe(4);
    expect(isCurrency("USD")).toBe(true);
    expect(isCurrency("usd")).toBe(false);
    expect(isCurrency(840)).toBe(false);
  });

  it("recognizes Money", () => {
    expect(isMoney(eur(1n))).toBe(true);
    expect(isMoney({ amount: 1, currency: "EUR" })).toBe(false);
    expect(isMoney({ amount: 1n, currency: "EURO" })).toBe(false);
    expect(isMoney(null)).toBe(false);
  });
});

describe("decimals", () => {
  it("parses and prints every minor unit", () => {
    expect(parseMoney("19.9", "EUR")).toEqual(eur(1990n));
    expect(parseMoney(" -0.05 ", "EUR")).toEqual(eur(-5n));
    expect(parseMoney("500", "JPY")).toEqual(money(500n, "JPY"));
    expect(parseMoney("1.234", "KWD")).toEqual(money(1234n, "KWD"));
    expect(toDecimal(eur(5n))).toBe("0.05");
    expect(toDecimal(eur(-1990n))).toBe("-19.90");
    expect(toDecimal(money(500n, "JPY"))).toBe("500");
  });

  it("refuses more decimals than the currency has instead of rounding", () => {
    expect(() => parseMoney("19.999", "EUR")).toThrow(/more decimals/);
    expect(() => parseMoney("1.5", "JPY")).toThrow(RangeError);
    expect(() => parseMoney("1,50", "EUR")).toThrow(/not a decimal/);
  });

  it("keeps every digit of amounts beyond a double", () => {
    const large = money(123_456_789_012_345_678_901n, "EUR");
    expect(toDecimal(large)).toBe("1234567890123456789.01");
    expect(formatMoney(large, "en-US")).toBe("€1,234,567,890,123,456,789.01");
  });

  it("formats with the locale and the currency's digits", () => {
    expect(formatMoney(eur(1999n), "nl-NL")).toBe("€\u00A019,99");
    expect(formatMoney(money(500n, "JPY"), "en-US")).toBe("¥500");
    expect(formatMoney(eur(1999n), "en-US", { currencyDisplay: "code" })).toBe(
      "EUR\u00A019.99",
    );
  });
});

describe("JSON", () => {
  it("writes the amount as a string and reads it back", () => {
    const json = moneyToJson(eur(-1999n));
    expect(json).toEqual({ amount: "-1999", currency: "EUR" });
    expect(JSON.parse(JSON.stringify(json))).toEqual(json);
    expect(moneyFromJson(json)).toEqual(eur(-1999n));
  });

  it("refuses anything else", () => {
    expect(() => moneyFromJson({ amount: 1999, currency: "EUR" })).toThrow(
      TypeError,
    );
    expect(() => moneyFromJson({ amount: "19.99", currency: "EUR" })).toThrow(
      TypeError,
    );
    expect(() => moneyFromJson("1999 EUR")).toThrow(TypeError);
    expect(() => moneyFromJson({ amount: "1", currency: "EURO" })).toThrow(
      RangeError,
    );
  });
});

describe("arithmetic", () => {
  it("adds, subtracts, sums, multiplies and negates in one currency", () => {
    expect(addMoney(eur(150n), eur(50n))).toEqual(eur(200n));
    expect(subtractMoney(eur(150n), eur(200n))).toEqual(eur(-50n));
    expect(sumMoney([eur(1n), eur(2n), eur(3n)], "EUR")).toEqual(eur(6n));
    expect(sumMoney([], "JPY")).toEqual(money(0n, "JPY"));
    expect(multiplyMoney(eur(250n), 3)).toEqual(eur(750n));
    expect(multiplyMoney(eur(250n), 3n)).toEqual(eur(750n));
    expect(negateMoney(eur(5n))).toEqual(eur(-5n));
    expect(() => multiplyMoney(eur(1n), 1.5)).toThrow(RangeError);
  });

  it("compares", () => {
    expect(compareMoney(eur(1n), eur(2n))).toBe(-1);
    expect(compareMoney(eur(2n), eur(2n))).toBe(0);
    expect(compareMoney(eur(3n), eur(2n))).toBe(1);
  });

  it("never mixes currencies", () => {
    const usd = money(1n, "USD");
    expect(() => addMoney(eur(1n), usd)).toThrow(CurrencyMismatchError);
    expect(() => subtractMoney(eur(1n), usd)).toThrow(TypeError);
    expect(() => compareMoney(eur(1n), usd)).toThrow(/EUR and USD/);
    expect(() => sumMoney([usd], "EUR")).toThrow(CurrencyMismatchError);
    expect(() => addMoney(eur(1n), usd)).toThrow(
      expect.objectContaining({ currencies: ["EUR", "USD"] }),
    );
  });
});

describe("roundHalfEven", () => {
  it("rounds ties to the even neighbour, both signs", () => {
    expect(roundHalfEven(5n, 2n)).toBe(2n);
    expect(roundHalfEven(7n, 2n)).toBe(4n);
    expect(roundHalfEven(-5n, 2n)).toBe(-2n);
    expect(roundHalfEven(-7n, 2n)).toBe(-4n);
    expect(roundHalfEven(5n, -2n)).toBe(-2n);
  });

  it("rounds everything else to the nearest", () => {
    expect(roundHalfEven(10n, 3n)).toBe(3n);
    expect(roundHalfEven(11n, 3n)).toBe(4n);
    expect(roundHalfEven(-11n, 3n)).toBe(-4n);
    expect(roundHalfEven(6n, 3n)).toBe(2n);
    expect(() => roundHalfEven(1n, 0n)).toThrow(/zero/);
  });
});

describe("applyRate", () => {
  it("multiplies by a decimal fraction, rounding half to even", () => {
    expect(applyRate(eur(1000n), "0.21")).toEqual(eur(210n));
    expect(applyRate(eur(250n), "0.09")).toEqual(eur(22n));
    expect(applyRate(eur(50n), "0.05")).toEqual(eur(2n));
    expect(applyRate(eur(70n), "0.05")).toEqual(eur(4n));
    expect(applyRate(eur(1000n), "0")).toEqual(eur(0n));
    expect(applyRate(eur(1000n), "1")).toEqual(eur(1000n));
  });

  it("takes the included part of an inclusive price", () => {
    expect(applyRate(eur(1210n), "0.21", { included: true })).toEqual(
      eur(210n),
    );
    expect(applyRate(eur(1000n), "0.21", { included: true })).toEqual(
      eur(174n),
    );
  });

  it("refuses a rate that isn't a decimal fraction", () => {
    expect(isRate("0.21")).toBe(true);
    expect(isRate("21%")).toBe(false);
    expect(isRate("-0.1")).toBe(false);
    expect(isRate(0.21)).toBe(false);
    expect(() => applyRate(eur(1n), "21%")).toThrow(/decimal fraction/);
  });
});

describe("allocateMoney", () => {
  it("splits so the parts add up exactly", () => {
    expect(allocateMoney(eur(100n), [1, 1, 1])).toEqual([
      eur(34n),
      eur(33n),
      eur(33n),
    ]);
    expect(allocateMoney(eur(1000n), [3n, 1n])).toEqual([eur(750n), eur(250n)]);
    expect(allocateMoney(eur(5n), [1, 0, 1])).toEqual([
      eur(3n),
      eur(0n),
      eur(2n),
    ]);
  });

  it("gives leftovers to the largest remainders", () => {
    expect(allocateMoney(eur(10n), [1, 2])).toEqual([eur(3n), eur(7n)]);
  });

  it("splits negative amounts the same way", () => {
    expect(allocateMoney(eur(-100n), [1, 1, 1])).toEqual([
      eur(-34n),
      eur(-33n),
      eur(-33n),
    ]);
  });

  it("refuses weights that can't split", () => {
    expect(() => allocateMoney(eur(1n), [0, 0])).toThrow(/more than 0/);
    expect(() => allocateMoney(eur(1n), [-1, 2])).toThrow(/negative/);
    expect(() => allocateMoney(eur(1n), [0.5])).toThrow(/whole weight/);
  });
});
