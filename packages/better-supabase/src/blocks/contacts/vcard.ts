/* oxlint-disable typescript/prefer-nullish-coalescing -- an empty string counts as missing in a card (6 findings) */
import type { CompanyInput, Company, Person, PersonInput } from "./contacts.ts";

import { SPEC_PINS } from "../../core/spec-pins.ts";

/** The vCard version the writer emits (RFC 6350). */
export const VCARD_VERSION = "4.0";

/** The media type of a `.vcf` file (RFC 6350 section 10.1). */
export const VCARD_MEDIA_TYPE = "text/vcard; charset=utf-8";

/** The RFC 6350 revision this module follows, from `SPEC_PINS`. */
export const VCARD_SPEC: typeof SPEC_PINS.rfc6350 = SPEC_PINS.rfc6350;

/** A postal address as vCard's `ADR` property holds it. */
export interface VCardAddress {
  readonly street?: string;
  readonly locality?: string;
  readonly region?: string;
  readonly postalCode?: string;
  readonly country?: string;
}

/** What `toVCard` writes: one contact, a person or an organization. */
export interface VCardContact {
  /** `individual` (default) or `org`. */
  readonly kind?: "individual" | "org";
  /** The formatted name, written as `FN` (required by RFC 6350 section 6.2.1). */
  readonly name: string;
  readonly givenName?: string;
  readonly familyName?: string;
  readonly organization?: string;
  readonly title?: string;
  readonly emails?: readonly string[];
  readonly phones?: readonly string[];
  readonly urls?: readonly string[];
  readonly addresses?: readonly VCardAddress[];
  readonly note?: string;
  /** A stable id, written as `UID:urn:uuid:...` when it is a UUID. */
  readonly uid?: string;
  /** Written as `REV`, in UTC. */
  readonly updatedAt?: Date;
}

/** What `parseVCards` returns for one card. */
export interface ParsedVCard {
  readonly kind: "individual" | "org";
  /** `FN`, or the structured name or organization when `FN` is empty. */
  readonly name: string;
  readonly givenName?: string;
  readonly familyName?: string;
  readonly organization?: string;
  readonly title?: string;
  readonly emails: readonly string[];
  readonly phones: readonly string[];
  readonly urls: readonly string[];
  readonly addresses: readonly VCardAddress[];
  readonly note?: string;
  readonly uid?: string;
}

/** A card `parseVCards` could not read, with its position in the file. */
export interface VCardSkipped {
  /** The zero-based index of the `BEGIN:VCARD` block. */
  readonly index: number;
  readonly reason: string;
}

export interface VCardParseResult {
  readonly cards: readonly ParsedVCard[];
  readonly skipped: readonly VCardSkipped[];
}

const CRLF = "\r\n";
const FOLD_OCTETS = 75;

// Created on first use: not every runtime has the global at import time.
let encoderInstance: InstanceType<typeof TextEncoder> | undefined;

const utf8Length = (text: string): number =>
  (encoderInstance ??= new TextEncoder()).encode(text).length;

/**
 * Escapes a text value (RFC 6350 section 3.4): backslash, comma, semicolon,
 * newline.
 */
function escapeText(value: string): string {
  return value
    .replaceAll("\\", String.raw`\\`)
    .replaceAll(";", String.raw`\;`)
    .replaceAll(",", String.raw`\,`)
    .replaceAll(/\r\n|\r|\n/g, String.raw`\n`);
}

/**
 * Folds a content line to 75 octets (RFC 6350 section 3.2), never inside a
 * multi-byte character.
 */
export function foldLine(line: string): string {
  if (utf8Length(line) <= FOLD_OCTETS) {
    return line;
  }

  const parts: string[] = [];
  let current = "";
  let limit = FOLD_OCTETS;

  for (const character of line) {
    if (utf8Length(current) + utf8Length(character) > limit) {
      parts.push(current);
      current = "";
      // A continuation line starts with one space, which counts as an octet.
      limit = FOLD_OCTETS - 1;
    }

    current += character;
  }

  parts.push(current);

  return parts.join(`${CRLF} `);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TEL_URI = /^\+?[0-9][0-9().\s-]{3,30}$/;

const pad = (value: number): string => String(value).padStart(2, "0");

function timestamp(date: Date): string {
  return `${String(date.getUTCFullYear())}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`;
}

function telLine(phone: string): string {
  const trimmed = phone.trim();

  if (TEL_URI.test(trimmed)) {
    const digits = trimmed.replaceAll(/[^+\d]/g, "");

    return `TEL;VALUE=uri:tel:${digits}`;
  }

  return `TEL;VALUE=text:${escapeText(trimmed)}`;
}

/**
 * One vCard 4.0 object (RFC 6350) with CRLF line ends. `FN` is always written;
 * an empty name becomes the first email, the organization or `Unnamed`.
 */
export function toVCard(contact: VCardContact): string {
  const name =
    contact.name.trim() ||
    contact.emails?.[0] ||
    contact.organization ||
    "Unnamed";

  const lines = ["BEGIN:VCARD", `VERSION:${VCARD_VERSION}`];

  if (contact.kind === "org") {
    lines.push("KIND:org");
  }

  lines.push(`FN:${escapeText(name)}`);

  if (contact.givenName !== undefined || contact.familyName !== undefined) {
    lines.push(
      `N:${escapeText(contact.familyName ?? "")};${escapeText(contact.givenName ?? "")};;;`,
    );
  }

  if (contact.organization) {
    lines.push(`ORG:${escapeText(contact.organization)}`);
  }

  if (contact.title) {
    lines.push(`TITLE:${escapeText(contact.title)}`);
  }

  for (const email of contact.emails ?? []) {
    lines.push(`EMAIL:${escapeText(email.trim())}`);
  }

  for (const phone of contact.phones ?? []) {
    lines.push(telLine(phone));
  }

  for (const url of contact.urls ?? []) {
    lines.push(`URL:${url.trim()}`);
  }

  for (const address of contact.addresses ?? []) {
    lines.push(
      `ADR:;;${[address.street, address.locality, address.region, address.postalCode, address.country].map((part) => escapeText(part ?? "")).join(";")}`,
    );
  }

  if (contact.note) {
    lines.push(`NOTE:${escapeText(contact.note)}`);
  }

  if (contact.uid) {
    lines.push(
      `UID:${UUID.test(contact.uid) ? `urn:uuid:${contact.uid.toLowerCase()}` : escapeText(contact.uid)}`,
    );
  }

  if (contact.updatedAt) {
    lines.push(`REV:${timestamp(contact.updatedAt)}`);
  }

  lines.push("END:VCARD");

  return lines.map(foldLine).join(CRLF) + CRLF;
}

/** Several contacts as one `.vcf` body. */
export function toVCards(contacts: readonly VCardContact[]): string {
  return contacts.map(toVCard).join("");
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.trim() !== "" ? value : undefined;

const addressOf = (
  value: Readonly<Record<string, unknown>> | undefined,
): VCardAddress[] => {
  if (value === undefined) {
    return [];
  }

  const street = text(value["street"]) ?? text(value["line1"]);
  const locality = text(value["city"]) ?? text(value["locality"]);
  const region = text(value["region"]) ?? text(value["state"]);
  const postalCode = text(value["postalCode"]) ?? text(value["postal_code"]);
  const country = text(value["country"]);

  if ([street, locality, region, postalCode, country].every((v) => !v)) {
    return [];
  }

  return [
    {
      ...(street === undefined ? {} : { street }),
      ...(locality === undefined ? {} : { locality }),
      ...(region === undefined ? {} : { region }),
      ...(postalCode === undefined ? {} : { postalCode }),
      ...(country === undefined ? {} : { country }),
    },
  ];
};

/** A person from `contacts.getPerson` or a list, as a `VCardContact`. */
export function personVCard(person: Person): VCardContact {
  const [givenName, ...rest] = person.name.split(" ");

  return {
    name: person.name,
    ...(rest.length > 0 && givenName !== undefined
      ? { givenName, familyName: rest.join(" ") }
      : {}),
    ...(person.title === undefined ? {} : { title: person.title }),
    ...(person.email === undefined ? {} : { emails: [person.email] }),
    ...(person.phone === undefined ? {} : { phones: [person.phone] }),
    uid: person.id,
  };
}

/** A company as a `VCardContact` of kind `org`. */
export function companyVCard(company: Company): VCardContact {
  const website = company.website ?? company.domain;

  return {
    kind: "org",
    name: company.name,
    organization: company.name,
    ...(website === undefined
      ? {}
      : {
          urls: [
            /^https?:\/\//i.test(website) ? website : `https://${website}`,
          ],
        }),
    addresses: addressOf(company.address),
    uid: company.id,
  };
}

/** The `.vcf` file of one person, company or any `VCardContact`. */
export interface VCardFile {
  readonly filename: string;
  readonly mediaType: string;
  readonly body: string;
}

const SAFE_NAME = /[^\p{L}\p{N}._ -]+/gu;

/** A file name with a `.vcf` extension and nothing a header or path can misread. */
export function vcardFilename(name: string): string {
  const base = name
    .replaceAll(SAFE_NAME, "")
    .trim()
    .replaceAll(/\s+/g, "-")
    .replace(/^[.-]+/, "");

  return `${base === "" ? "contact" : base.slice(0, 80)}.vcf`;
}

/** The `.vcf` of one contact. */
export function vcardFile(contact: VCardContact): VCardFile {
  return {
    filename: vcardFilename(contact.name),
    mediaType: VCARD_MEDIA_TYPE,
    body: toVCard(contact),
  };
}

/**
 * The `.vcf` of a list, one card per contact, named `filename` (default
 * `contacts`).
 */
export function vcardListFile(
  contacts: readonly VCardContact[],
  filename = "contacts",
): VCardFile {
  return {
    filename: vcardFilename(filename),
    mediaType: VCARD_MEDIA_TYPE,
    body: toVCards(contacts),
  };
}

/** A download `Response` for a `VCardFile`: `Content-Disposition: attachment`. */
export function vcardResponse(file: VCardFile): Response {
  return new Response(file.body, {
    headers: {
      "content-type": file.mediaType,
      "content-disposition": `attachment; filename="${file.filename.replaceAll('"', "")}"`,
      "cache-control": "no-store",
    },
  });
}

/**
 * Content lines of a vCard body with folded lines joined (RFC 6350 section
 * 3.2).
 */
function unfold(body: string): string[] {
  return body
    .replaceAll(/\r\n|\r/g, "\n")
    .replaceAll(/\n[ \t]/g, "")
    .split("\n");
}

interface Property {
  readonly name: string;
  readonly params: ReadonlyMap<string, string>;
  readonly value: string;
}

function splitOnce(line: string): { head: string; value: string } | undefined {
  // The first colon outside a quoted parameter value separates name and value.
  let quoted = false;

  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];

    if (character === '"') {
      quoted = !quoted;
    } else if (character === ":" && !quoted) {
      return { head: line.slice(0, index), value: line.slice(index + 1) };
    }
  }

  return undefined;
}

function property(line: string): Property | undefined {
  const parts = splitOnce(line);

  if (parts === undefined) {
    return undefined;
  }

  const [rawName = "", ...rawParams] = parts.head.split(";");
  const name = (rawName.split(".").pop() ?? "").toUpperCase();
  const params = new Map<string, string>();

  for (const raw of rawParams) {
    const equals = raw.indexOf("=");

    if (equals > 0) {
      params.set(
        raw.slice(0, equals).toUpperCase(),
        raw.slice(equals + 1).replaceAll('"', ""),
      );
    }
  }

  return { name, params, value: parts.value };
}

function unescapeText(value: string): string {
  let result = "";

  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];

    if (character === "\\" && index + 1 < value.length) {
      const next = value[index + 1];
      result += next === "n" || next === "N" ? "\n" : (next ?? "");
      index += 1;
    } else {
      result += character;
    }
  }

  return result;
}

/** Splits a structured value on unescaped semicolons. */
function components(value: string): string[] {
  const parts: string[] = [];
  let current = "";

  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];

    if (character === "\\" && index + 1 < value.length) {
      current += `${character}${value[index + 1] ?? ""}`;
      index += 1;
    } else if (character === ";") {
      parts.push(current);
      current = "";
    } else {
      current += character;
    }
  }

  parts.push(current);

  return parts.map(unescapeText);
}

function build(properties: readonly Property[]): ParsedVCard | string {
  const first = (name: string): Property | undefined =>
    properties.find((item) => item.name === name);

  const all = (name: string): Property[] =>
    properties.filter((item) => item.name === name);

  const version = first("VERSION")?.value.trim();

  if (version !== "4.0" && version !== "3.0" && version !== "2.1") {
    return "VERSION is missing or not 2.1, 3.0 or 4.0";
  }

  const structured = components(first("N")?.value ?? "");
  const familyName = structured[0]?.trim() || undefined;
  const givenName = structured[1]?.trim() || undefined;

  const organization =
    components(first("ORG")?.value ?? "")[0]?.trim() || undefined;

  const formatted = unescapeText(first("FN")?.value ?? "").trim();

  const kind =
    first("KIND")?.value.trim().toLowerCase() === "org" ? "org" : "individual";

  const name =
    formatted ||
    [givenName, familyName].filter(Boolean).join(" ") ||
    organization ||
    "";

  if (name === "") {
    return "FN is missing";
  }

  const telephone = (item: Property): string => {
    const raw = unescapeText(item.value).trim();

    return raw.toLowerCase().startsWith("tel:") ? raw.slice(4) : raw;
  };

  const addresses = all("ADR").map((item): VCardAddress => {
    const [, , street, locality, region, postalCode, country] = components(
      item.value,
    );

    return {
      ...(street ? { street } : {}),
      ...(locality ? { locality } : {}),
      ...(region ? { region } : {}),
      ...(postalCode ? { postalCode } : {}),
      ...(country ? { country } : {}),
    };
  });

  const note = unescapeText(first("NOTE")?.value ?? "").trim();
  const title = unescapeText(first("TITLE")?.value ?? "").trim();
  const uid = unescapeText(first("UID")?.value ?? "").trim();

  return {
    kind,
    name,
    ...(givenName === undefined ? {} : { givenName }),
    ...(familyName === undefined ? {} : { familyName }),
    ...(organization === undefined ? {} : { organization }),
    ...(title === "" ? {} : { title }),
    emails: all("EMAIL").flatMap((item) => {
      const email = unescapeText(item.value).trim();

      return email === "" ? [] : [email];
    }),
    phones: all("TEL").flatMap((item) => {
      const phone = telephone(item);

      return phone ? [phone] : [];
    }),
    urls: all("URL").flatMap((item) => {
      const url = item.value.trim();

      return url === "" ? [] : [url];
    }),
    addresses: addresses.filter((address) => Object.keys(address).length > 0),
    ...(note === "" ? {} : { note }),
    ...(uid === "" ? {} : { uid }),
  };
}

/**
 * Reads every vCard of a `.vcf` body (RFC 6350; 2.1 and 3.0 files read too). It
 * never throws: a card without `VERSION` or a name lands in `skipped` with a
 * reason, and the rest are returned.
 */
export function parseVCards(body: string): VCardParseResult {
  const cards: ParsedVCard[] = [];
  const skipped: VCardSkipped[] = [];
  let current: Property[] | undefined;
  let index = -1;

  for (const line of unfold(body)) {
    const trimmed = line.trim();

    if (trimmed.toUpperCase() === "BEGIN:VCARD") {
      index += 1;
      current = [];
    } else if (trimmed.toUpperCase() === "END:VCARD") {
      if (current !== undefined) {
        const card = build(current);

        if (typeof card === "string") {
          skipped.push({ index, reason: card });
        } else {
          cards.push(card);
        }
      }

      current = undefined;
    } else if (current !== undefined && trimmed !== "") {
      const parsed = property(line);

      if (parsed !== undefined) {
        current.push(parsed);
      }
    }
  }

  if (current !== undefined) {
    skipped.push({ index, reason: "END:VCARD is missing" });
  }

  return { cards, skipped };
}

/** A `PersonInput` for `contacts.savePerson` from an imported card. */
export function vcardToPersonInput(card: ParsedVCard): PersonInput {
  return {
    name: card.name,
    ...(card.emails[0] === undefined ? {} : { email: card.emails[0] }),
    ...(card.phones[0] === undefined ? {} : { phone: card.phones[0] }),
    ...(card.title === undefined ? {} : { title: card.title }),
  };
}

/** A `CompanyInput` for `contacts.saveCompany` from an imported card. */
export function vcardToCompanyInput(card: ParsedVCard): CompanyInput {
  const [address] = card.addresses;

  return {
    name: card.organization ?? card.name,
    ...(card.urls[0] === undefined ? {} : { website: card.urls[0] }),
    ...(address === undefined
      ? {}
      : {
          address: {
            ...(address.street ? { street: address.street } : {}),
            ...(address.locality ? { city: address.locality } : {}),
            ...(address.region ? { region: address.region } : {}),
            ...(address.postalCode ? { postalCode: address.postalCode } : {}),
            ...(address.country ? { country: address.country } : {}),
          },
        }),
  };
}
