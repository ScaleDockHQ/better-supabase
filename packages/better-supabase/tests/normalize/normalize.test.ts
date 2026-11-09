import { describe, expect, it } from "vitest";

import {
  TEXT_PACKS,
  detectMojibake,
  looksShouted,
  normalizeBic,
  normalizeEmail,
  normalizeName,
  normalizeNationalId,
  normalizePhone,
  normalizePostalCode,
  sanitizeText,
  splitPersonName,
  classifyParty,
  splitStreet,
  validateIban,
} from "../../src/normalize/index.ts";

describe("normalize", () => {
  it("keeps initials and particles apart", () => {
    expect(splitPersonName("A. Gerritsen").display).toBe("A. Gerritsen");
    expect(splitPersonName("A.M. Gerritsen").initials).toBe("A.M.");
    expect(splitPersonName("H. Gerritsen").initials).toBe("H.");
    expect(splitPersonName("Jan van der Berg")).toEqual({
      given: "Jan",
      initials: "",
      infix: "van der",
      last: "Berg",
      display: "Jan van der Berg",
    });
  });

  it("classifies people, families and companies", () => {
    const rows = ["A. Gerritsen", "A.M. Gerritsen", "H. Gerritsen"].map(
      (name) => classifyParty(name),
    );

    expect(rows.map((row) => row.displayName)).toEqual([
      "A. Gerritsen",
      "A.M. Gerritsen",
      "H. Gerritsen",
    ]);
    expect(new Set(rows.map((row) => row.initials)).size).toBe(3);
    expect(classifyParty("Jan van der Berg").given).toBe("Jan");
    expect(classifyParty("Piet en Marie Jansen").displayName).toContain("Piet");
    expect(classifyParty("Piet en Marie Jansen").displayName).toContain(
      "Marie",
    );
    expect(classifyParty("Bakkerij Jansen bv")).toMatchObject({
      kind: "company",
      legalName: "Bakkerij Jansen bv",
    });
    expect(classifyParty("Bakkerij Jansen bv", "person").kind).toBe("person");
  });

  it("is idempotent for names, phones and postal codes", () => {
    const name = normalizeName("T. LOMAN sr.");
    expect(normalizeName(name)).toBe(name);
    expect(name).toBe("T. Loman sr.");

    const phone = normalizePhone("06 12345678", { defaultRegion: "NL" });
    expect(normalizePhone(phone, { defaultRegion: "NL" })).toBe(phone);
    expect(phone).toBe("+31612345678");

    const postal = normalizePostalCode("1012ab", { country: "NL" });
    expect(normalizePostalCode(postal, { country: "NL" })).toBe(postal);
    expect(postal).toBe("1012 AB");
  });

  it("checks an IBAN and a BIC", () => {
    expect(validateIban("NL91 ABNA 0417 1643 00")).toBe(true);
    expect(validateIban("NL91 ABNA 0417 1643 01")).toBe(false);
    expect(normalizeBic("abna nl 2a")).toBe("ABNANL2A");
    expect(normalizeBic("nope")).toBe("");
  });

  it("splits a street and a chamber of commerce number", () => {
    expect(splitStreet("Keizersgracht 12 hs", { country: "NL" })).toEqual({
      street: "Keizersgracht",
      number: "12",
      addition: "hs",
    });
    expect(normalizeNationalId("1234 5678", { country: "NL" })).toBe(
      "12345678",
    );
    expect(normalizeEmail(" Ada@Example.com ")).toBe("ada@example.com");
  });

  it("repairs each named pack once and does not lengthen the text", () => {
    for (const [, pack] of Object.entries(TEXT_PACKS)) {
      for (const repair of pack) {
        const once = sanitizeText(repair.pattern, { repairs: pack });
        expect(sanitizeText(once, { repairs: pack })).toBe(once);
        expect(once.length).toBeLessThanOrEqual(repair.pattern.length);
        expect(once).not.toContain(repair.pattern);
      }
    }
  });

  it("strips a csv quote and scores mojibake", () => {
    expect(sanitizeText('"Widget"', { csvQuotes: true })).toBe("Widget");
    expect(sanitizeText("`Widget", { csvQuotes: true })).toBe("Widget");
    expect(sanitizeText("a\u0001b\t\tc", { stripControl: true })).toBe("ab c");
    expect(detectMojibake("cafÃ©")).toBeGreaterThan(0);
    expect(detectMojibake("cafe")).toBe(0);
    expect(looksShouted("T. LOMAN sr.")).toBe(true);
    expect(looksShouted("A. Gerritsen")).toBe(false);
    expect(looksShouted("")).toBe(false);
  });

  it("fills the other phone, postal and street shapes", () => {
    expect(normalizePhone("0031612345678")).toBe("+31612345678");
    expect(normalizePhone("31612345678", { defaultRegion: "zz" })).toBe(
      "31612345678",
    );
    expect(normalizePhone("316", { defaultRegion: "nl" })).toBe("+31316");
    expect(normalizePostalCode("not a code", { country: "NL" })).toBe(
      "NOT A CODE",
    );
    expect(normalizePostalCode("10 115", { country: "de" })).toBe("10115");
    expect(normalizePostalCode("12345-6789", { country: "US" })).toBe(
      "12345-6789",
    );
    expect(normalizePostalCode("12345", { country: "US" })).toBe("12345");
    expect(normalizePostalCode(" 10115 ")).toBe("10115");
    expect(splitStreet("Main Street", { country: "US" })).toEqual({
      street: "Main Street",
      number: "",
      addition: "",
    });
    expect(normalizeNationalId("12345678", { country: "nl" })).toBe("12345678");
    expect(normalizeNationalId("12", { country: "NL" })).toBe("");
    expect(normalizeNationalId("12-34", { country: "US" })).toBe("1234");
    expect(splitPersonName("van Berg")).toMatchObject({
      infix: "van",
      given: "",
      last: "Berg",
    });
  });
});
