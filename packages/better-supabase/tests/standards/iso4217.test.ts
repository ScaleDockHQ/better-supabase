import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { ISO_4217_MINOR_UNITS } from "../../src/blocks/commerce/iso4217.ts";
import {
  minorUnits,
  money,
  toDecimal,
} from "../../src/blocks/commerce/money.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const listOne = await readFile(
  new URL("schemas/iso-4217-list-one-2026-09-17.xml", import.meta.url),
  "utf8",
);

const fromListOne = (): Record<string, number> => {
  const units: Record<string, number> = {};
  for (const [, entry] of listOne.matchAll(/<CcyNtry>([\s\S]*?)<\/CcyNtry>/g)) {
    const code = /<Ccy>([A-Z]{3})<\/Ccy>/.exec(entry ?? "")?.[1];
    const minor = /<CcyMnrUnts>(\d+)<\/CcyMnrUnts>/.exec(entry ?? "")?.[1];
    if (code !== undefined && minor !== undefined) units[code] = Number(minor);
  }
  return units;
};

describe("ISO 4217", () => {
  it("pins the List One publication the vendored file carries", () => {
    expect(SPEC_PINS.iso4217).toBe("2026-09-17");
    expect(listOne).toContain(`<ISO_4217 Pblshd="${SPEC_PINS.iso4217}">`);
  });

  it("has the minor units of every List One code, and no other code", () => {
    expect({ ...ISO_4217_MINOR_UNITS }).toEqual(fromListOne());
  });

  it("leaves out codes without minor units, such as gold", () => {
    expect(listOne).toContain("<Ccy>XAU</Ccy>");
    expect(() => minorUnits("XAU")).toThrow(RangeError);
  });

  it("formats amounts with each currency's exponent", () => {
    expect(toDecimal(money(1234n, "EUR"))).toBe("12.34");
    expect(toDecimal(money(1234n, "JPY"))).toBe("1234");
    expect(toDecimal(money(1234n, "KWD"))).toBe("1.234");
    expect(toDecimal(money(12_345n, "CLF"))).toBe("1.2345");
  });
});
