import { describe, expect, it } from "vitest";

import type { Company, Person } from "../../../src/blocks/contacts/contacts.ts";

import {
  companyVCard,
  parseVCards,
  personVCard,
  toVCard,
  vcardFile,
  vcardFilename,
  vcardListFile,
  vcardResponse,
  vcardToCompanyInput,
  vcardToPersonInput,
} from "../../../src/blocks/contacts/vcard.ts";

const person = {
  id: "0b9d3c0e-6b8f-4a53-b3a4-1d2c3e4f5a6b",
  organizationId: "o",
  name: "Ada Lovelace",
  lifecycle: "lead",
  archived: false,
  roles: [],
  fields: {},
  email: "ada@example.com",
  phone: "+31 6 1234 5678",
  title: "Analyst",
} satisfies Person;

describe("vCard export", () => {
  it("writes a person with a tel URI and a urn:uuid UID", () => {
    const card = toVCard(personVCard(person));

    expect(card).toContain("FN:Ada Lovelace");
    expect(card).toContain("N:Lovelace;Ada;;;");
    expect(card).toContain("EMAIL:ada@example.com");
    expect(card).toContain("TEL;VALUE=uri:tel:+31612345678");
    expect(card).toContain("TITLE:Analyst");
    expect(card).toContain(`UID:urn:uuid:${person.id}`);
  });

  it("writes a company as KIND:org with a url and an address", () => {
    const company = {
      ...person,
      name: "Acme, Inc",
      website: "acme.example",
      address: { street: "1 Main St", city: "Springfield", country: "USA" },
    } as unknown as Company;

    const card = toVCard(companyVCard(company));

    expect(card).toContain("KIND:org");
    expect(card).toContain(String.raw`ORG:Acme\, Inc`);
    expect(card).toContain("URL:https://acme.example");
    expect(card).toContain("ADR:;;1 Main St;Springfield;;;USA");
  });

  it("names download files safely", () => {
    expect(vcardFilename('../Ada "L"/x')).toBe("Ada-Lx.vcf");
    expect(vcardFilename("")).toBe("contact.vcf");
    expect(vcardFile(personVCard(person)).filename).toBe("Ada-Lovelace.vcf");
  });

  it("builds a list file and a download response", async () => {
    const file = vcardListFile(
      [personVCard(person), { name: "Second" }],
      "Team",
    );

    expect(file.filename).toBe("Team.vcf");
    expect(file.body.match(/BEGIN:VCARD/g)).toHaveLength(2);

    const response = vcardResponse(file);

    expect(response.headers.get("content-type")).toBe(
      "text/vcard; charset=utf-8",
    );
    expect(response.headers.get("content-disposition")).toBe(
      'attachment; filename="Team.vcf"',
    );
    expect(await response.text()).toBe(file.body);
  });
});

describe("vCard import", () => {
  it("round-trips an exported person", () => {
    const { cards, skipped } = parseVCards(toVCard(personVCard(person)));

    expect(skipped).toEqual([]);
    expect(cards[0]).toMatchObject({
      kind: "individual",
      name: "Ada Lovelace",
      givenName: "Ada",
      familyName: "Lovelace",
      emails: ["ada@example.com"],
      phones: ["+31612345678"],
      title: "Analyst",
    });
    expect(vcardToPersonInput(cards[0]!)).toEqual({
      name: "Ada Lovelace",
      email: "ada@example.com",
      phone: "+31612345678",
      title: "Analyst",
    });
  });

  it("reads several cards, groups and a 3.0 card, and skips broken ones", () => {
    const body = [
      "BEGIN:VCARD",
      "VERSION:3.0",
      "FN:Old Style",
      "item1.EMAIL;TYPE=INTERNET:old@example.com",
      "END:VCARD",
      "BEGIN:VCARD",
      "VERSION:4.0",
      "EMAIL:noname@example.com",
      "END:VCARD",
      "BEGIN:VCARD",
      "FN:No Version",
      "END:VCARD",
      "BEGIN:VCARD",
      "VERSION:4.0",
      "FN:Unfinished",
    ].join("\r\n");

    const result = parseVCards(body);

    expect(result.cards.map((card) => card.name)).toEqual(["Old Style"]);
    expect(result.cards[0]?.emails).toEqual(["old@example.com"]);
    expect(result.skipped).toEqual([
      { index: 1, reason: "FN is missing" },
      { index: 2, reason: "VERSION is missing or not 2.1, 3.0 or 4.0" },
      { index: 3, reason: "END:VCARD is missing" },
    ]);
  });

  it("maps an organization card to a company input", () => {
    const { cards } = parseVCards(
      "BEGIN:VCARD\r\nVERSION:4.0\r\nKIND:org\r\nFN:Acme\r\nORG:Acme BV\r\nURL:https://acme.example\r\nADR:;;1 Main St;Springfield;;1234;NL\r\nEND:VCARD\r\n",
    );

    expect(cards[0]?.kind).toBe("org");
    expect(vcardToCompanyInput(cards[0]!)).toEqual({
      name: "Acme BV",
      website: "https://acme.example",
      address: {
        street: "1 Main St",
        city: "Springfield",
        postalCode: "1234",
        country: "NL",
      },
    });
  });
});
