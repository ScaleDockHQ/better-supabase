import { describe, expect, it } from "vitest";

import {
  foldLine,
  parseVCards,
  toVCard,
} from "../../src/blocks/contacts/vcard.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("RFC 6350 vCard 4.0", () => {
  it("pins the revision", () => {
    expect(SPEC_PINS.rfc6350).toBe("2011-08");
  });

  it("starts with BEGIN and VERSION and ends with END, with CRLF line ends", () => {
    const card = toVCard({ name: "Ada Lovelace" });
    const lines = card.split("\r\n");

    expect(lines[0]).toBe("BEGIN:VCARD");
    expect(lines[1]).toBe("VERSION:4.0");
    expect(lines.at(-2)).toBe("END:VCARD");
    expect(card.endsWith("\r\n")).toBe(true);
    expect(card.replaceAll("\r\n", "")).not.toContain("\n");
  });

  it("writes FN even when the name is empty", () => {
    expect(toVCard({ name: "", emails: ["a@example.com"] })).toContain(
      "FN:a@example.com",
    );
  });

  it("escapes backslash, comma, semicolon and newline (section 3.4)", () => {
    const card = toVCard({ name: "Doe, John; Jr", note: "a\\b\nc" });

    expect(card).toContain(String.raw`FN:Doe\, John\; Jr`);
    expect(card).toContain(String.raw`NOTE:a\\b\nc`);
  });

  it("folds lines to 75 octets without cutting a character (section 3.2)", () => {
    const folded = foldLine(`NOTE:${"é".repeat(80)}`);

    for (const line of folded.split("\r\n")) {
      expect(new TextEncoder().encode(line).length).toBeLessThanOrEqual(75);
    }

    const parsed = parseVCards(
      `BEGIN:VCARD\r\nVERSION:4.0\r\nFN:X\r\n${folded}\r\nEND:VCARD\r\n`,
    );

    expect(parsed.cards[0]?.note).toBe("é".repeat(80));
  });

  it("reads the ADR components in order (section 6.3.1)", () => {
    const { cards } = parseVCards(
      "BEGIN:VCARD\nVERSION:4.0\nFN:Acme\nADR;TYPE=work:;;1 Main St;Springfield;IL;62701;USA\nEND:VCARD\n",
    );

    expect(cards[0]?.addresses).toEqual([
      {
        street: "1 Main St",
        locality: "Springfield",
        region: "IL",
        postalCode: "62701",
        country: "USA",
      },
    ]);
  });
});
