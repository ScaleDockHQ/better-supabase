import { describe, expect, it } from "vitest";

import type { Company, Person } from "../../../src/blocks/contacts/contacts.ts";

import {
  companyVCard,
  foldLine,
  parseVCards,
  personVCard,
  toVCard,
  toVCards,
  vcardFilename,
  vcardToCompanyInput,
  vcardToPersonInput,
} from "../../../src/blocks/contacts/vcard.ts";

const basePerson = {
  id: "p1",
  organizationId: "o",
  name: "Cher",
  lifecycle: "lead",
  archived: false,
  roles: [],
  fields: {},
} satisfies Person;

const baseCompany = {
  id: "c1",
  organizationId: "o",
  name: "Acme",
  lifecycle: "lead",
  archived: false,
  roles: [],
  fields: {},
} satisfies Company;

const company = (extra: Partial<Company>): Company => ({
  ...baseCompany,
  ...extra,
});

const card = (...lines: string[]): string =>
  ["BEGIN:VCARD", "VERSION:4.0", ...lines, "END:VCARD"].join("\r\n");

describe("vCard writer edges", () => {
  it("falls back to the email, organization or Unnamed for FN", () => {
    expect(toVCard({ name: " ", emails: ["a@b.c"] })).toContain("FN:a@b.c");
    expect(toVCard({ name: "", organization: "Org" })).toContain("FN:Org");
    expect(toVCard({ name: "" })).toContain("FN:Unnamed");
  });

  it("writes every optional property and escapes text", () => {
    const body = toVCard({
      kind: "org",
      name: "A;B",
      givenName: "Gi",
      organization: "Org, Inc",
      title: "T\\x",
      emails: [" e@x.y "],
      phones: ["+31 6 1234", "call me"],
      urls: [" https://x.y "],
      addresses: [{ street: "S", locality: "L", region: "R" }, {}],
      note: "line1\nline2",
      uid: "not-a-uuid",
      updatedAt: new Date("2026-01-02T03:04:05Z"),
    });

    expect(body).toContain("KIND:org");
    expect(body).toContain(String.raw`FN:A\;B`);
    expect(body).toContain("N:;Gi;;;");
    expect(body).toContain("TEL;VALUE=uri:tel:+316123456".slice(0, 20));
    expect(body).toContain("TEL;VALUE=text:call me");
    expect(body).toContain("URL:https://x.y");
    expect(body).toContain("ADR:;;S;L;R;;");
    expect(body).toContain("ADR:;;;;;;");
    expect(body).toContain(String.raw`NOTE:line1\nline2`);
    expect(body).toContain("UID:not-a-uuid");
    expect(body).toContain("REV:20260102T030405Z");
  });

  it("writes a family name only and folds long lines", () => {
    expect(toVCard({ name: "X", familyName: "Fam" })).toContain("N:Fam;;;;");

    const long = foldLine("é".repeat(100));

    expect(long).toContain("\r\n ");
    expect(foldLine("short")).toBe("short");
    expect(toVCards([{ name: "A" }, { name: "B" }])).toContain("FN:B");
  });

  it("maps people and companies with and without optional fields", () => {
    expect(personVCard(basePerson)).toEqual({ name: "Cher", uid: "p1" });
    expect(personVCard({ ...basePerson, name: "A B C" })).toMatchObject({
      givenName: "A",
      familyName: "B C",
    });

    expect(companyVCard(company({}))).toMatchObject({
      kind: "org",
      addresses: [],
    });
    expect(companyVCard(company({ domain: "acme.example" })).urls).toEqual([
      "https://acme.example",
    ]);
    expect(
      companyVCard(company({ website: "HTTP://acme.example" })).urls,
    ).toEqual(["HTTP://acme.example"]);
    expect(
      companyVCard(
        company({
          address: {
            line1: "1 St",
            locality: "Town",
            state: "ST",
            postal_code: "99",
            country: "US",
            street: " ",
          },
        }),
      ).addresses,
    ).toEqual([
      {
        street: "1 St",
        locality: "Town",
        region: "ST",
        postalCode: "99",
        country: "US",
      },
    ]);
    expect(
      companyVCard(company({ address: { country: 5, city: "" } })).addresses,
    ).toEqual([]);
  });

  it("names files from long or symbol-only names", () => {
    expect(vcardFilename("***")).toBe("contact.vcf");
    expect(vcardFilename("a".repeat(120))).toBe(`${"a".repeat(80)}.vcf`);
  });
});

describe("vCard reader edges", () => {
  it("reads escapes, groups, quoted parameters and structured values", () => {
    const { cards, skipped } = parseVCards(
      card(
        String.raw`N:Fam\;ily;Giv;;;`,
        'item1.TEL;TYPE="a:b";VALUE=uri:tel:+3161',
        "TEL:call",
        "TEL:",
        String.raw`NOTE:a\nb\Nc\,d\\`,
        "TITLE:  Boss ",
        "UID:urn:uuid:abc",
        "EMAIL:",
        "URL:",
        "URL: https://x.y ",
        "BADLINE-WITHOUT-COLON",
        "X;NOEQUALS=:v",
        String.raw`ADR:;;St\;r;City;Reg;Zip;Land`,
        "ADR:;;;;;;",
        "ORG:Org\\;Part;Unit",
      ),
    );

    expect(skipped).toEqual([]);
    expect(cards[0]).toMatchObject({
      kind: "individual",
      name: "Giv Fam;ily",
      familyName: "Fam;ily",
      givenName: "Giv",
      organization: "Org;Part",
      phones: ["+3161", "call"],
      urls: ["https://x.y"],
      emails: [],
      note: "a\nb\nc,d\\",
      title: "Boss",
      uid: "urn:uuid:abc",
      addresses: [
        {
          street: "St;r",
          locality: "City",
          region: "Reg",
          postalCode: "Zip",
          country: "Land",
        },
      ],
    });
  });

  it("uses the organization as the name and reads 2.1 and bare lines", () => {
    const body = [
      "begin:vcard",
      "VERSION:2.1",
      "KIND:ORG",
      "ORG:OnlyOrg",
      "end:vcard",
      "stray line outside",
      "BEGIN:VCARD",
      "VERSION:3.0",
      "",
      "FN:Folded",
      " Name",
      "END:VCARD",
      "END:VCARD",
    ].join("\n");

    const { cards, skipped } = parseVCards(body);

    expect(skipped).toEqual([]);
    expect(cards.map((c) => c.name)).toEqual(["OnlyOrg", "FoldedName"]);
    expect(cards[0]?.kind).toBe("org");
    expect(cards[0]?.title).toBeUndefined();
    expect(cards[0]?.note).toBeUndefined();
    expect(cards[0]?.uid).toBeUndefined();
  });

  it("converts cards into inputs with and without optional data", () => {
    const [bare] = parseVCards(card("FN:Bare")).cards;

    expect(vcardToPersonInput(bare!)).toEqual({ name: "Bare" });
    expect(vcardToCompanyInput(bare!)).toEqual({ name: "Bare" });

    const [partial] = parseVCards(
      card("FN:P", "ORG:Corp", "ADR:;;;Town;;;"),
    ).cards;

    expect(vcardToCompanyInput(partial!)).toEqual({
      name: "Corp",
      address: { city: "Town" },
    });
  });
});
