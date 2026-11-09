/**
 * Importer-facing text helpers. Locale rules live in the data tables below, so
 * a country is a new row, not a new branch in the functions.
 */

/** A literal repair. `pattern` is matched as text, not as a regular expression. */
export interface TextRepair {
  readonly pattern: string;
  readonly replacement: string;
}

export interface PersonName {
  /** Written given name, empty when the source only has initials. */
  readonly given: string;
  /** Initials as written, including the dots. Never expanded or dropped. */
  readonly initials: string;
  /** Name particles such as `van der`, empty when there are none. */
  readonly infix: string;
  readonly last: string;
  /** The name to show: initials or given name, then infix, then last name. */
  readonly display: string;
}

export interface PhoneOptions {
  /** Region used when the number has a national trunk prefix, such as `NL`. */
  readonly defaultRegion?: string;
}

export interface CountryOptions {
  readonly country?: string;
}

export interface SanitizeOptions {
  readonly repairs?: readonly TextRepair[];
  /** Drop C0 controls and DEL. Tabs, newlines and inch marks stay. */
  readonly stripControl?: boolean;
  /** Drop a wrapping CSV quote and a leading quote cut off mid field. */
  readonly csvQuotes?: boolean;
}

/** Calling codes, keyed by ISO 3166-1 alpha-2. */
const CALLING: Readonly<Record<string, string>> = {
  NL: "31",
  DE: "49",
  FR: "33",
  GB: "44",
  US: "1",
};

/** Particles that sit between a given name and a last name, longest first. */
const PARTICLES = ["van de", "van der", "van den", "van", "der", "den", "de"];

const SHOUTED_WORD = /^[A-Z]{3,}$/;

/**
 * UTF-8 bytes read as Latin-1. Each replacement is the decoded character, so a
 * second pass finds no pattern.
 */
const UTF8_AS_LATIN1: readonly TextRepair[] = [
  { pattern: "Ã©", replacement: "é" },
  { pattern: "Ã¨", replacement: "è" },
  { pattern: "Ãª", replacement: "ê" },
  { pattern: "Ã«", replacement: "ë" },
  { pattern: "Ã¶", replacement: "ö" },
  { pattern: "Ã¼", replacement: "ü" },
  { pattern: "Ã¤", replacement: "ä" },
  { pattern: "Ã±", replacement: "ñ" },
  { pattern: "ÃŸ", replacement: "ß" },
  { pattern: "Ã¡", replacement: "á" },
];

/** Windows-1252 punctuation that arrives as UTF-8 read through Latin-1. */
const WINDOWS_1252: readonly TextRepair[] = [
  { pattern: "â€™", replacement: "'" },
  { pattern: "â€œ", replacement: '"' },
  { pattern: "â€\u009D", replacement: '"' },
  { pattern: "â€“", replacement: "-" },
  { pattern: "â€”", replacement: "-" },
  { pattern: "Â ", replacement: " " },
];

/** CP437 glyphs that a Latin-1 reader keeps as the wrong letter. */
const CP437: readonly TextRepair[] = [{ pattern: "Γ", replacement: "É" }];

/** CP850 byte 0xE6 shown as micro when the file was CP850. */
const CP850: readonly TextRepair[] = [{ pattern: "µ", replacement: "Á" }];

/** Named repair lists. No pattern for one source is built into `sanitizeText`. */
export const TEXT_PACKS: Readonly<Record<string, readonly TextRepair[]>> = {
  "utf8-as-latin1": UTF8_AS_LATIN1,
  "windows-1252": WINDOWS_1252,
  cp437: CP437,
  cp850: CP850,
};

const replaceOnce = (value: string, repair: TextRepair): string =>
  repair.pattern === ""
    ? value
    : value.split(repair.pattern).join(repair.replacement);

/** Collapse whitespace and turn a shouted name into words with one capital. */
export function normalizeName(value: string): string {
  const trimmed = value
    .trim()
    .replaceAll(/\s+/g, " ")
    .replace(/^['"`]+/u, "");

  if (!looksShouted(trimmed)) {
    return trimmed;
  }

  return trimmed
    .split(" ")
    .map((word) =>
      SHOUTED_WORD.test(word)
        ? word.charAt(0) + word.slice(1).toLowerCase()
        : word,
    )
    .join(" ");
}

/**
 * Split a person name. Initials stay initials, so `A. Gerritsen` and `A.M.
 * Gerritsen` stay different. Particles stay in `infix`.
 */
export function splitPersonName(value: string): PersonName {
  const tokens = normalizeName(value)
    .split(" ")
    .filter((token) => token !== "");

  const initials: string[] = [];

  while (tokens[0] !== undefined && /^[A-Z](?:\.[A-Z])*\.?$/u.test(tokens[0])) {
    const token = tokens.shift()!;
    initials.push(token.endsWith(".") ? token : `${token}.`);
  }

  const last = tokens.pop() ?? "";
  const head = tokens.join(" ");
  let infix = "";
  let given = head;

  for (const particle of PARTICLES) {
    if (head.toLowerCase() === particle) {
      infix = particle;
      given = "";
      break;
    }

    const tail = ` ${particle}`;

    if (head.toLowerCase().endsWith(tail)) {
      infix = particle;
      given = head.slice(0, -tail.length);
      break;
    }
  }

  const display = [initials.join(" ") || given, infix, last]
    .filter((part) => part !== "")
    .join(" ");

  return { given, initials: initials.join(" "), infix, last, display };
}

const BUSINESS_MARK =
  /\b(?:b\.?v\.?|n\.?v\.?|gmbh|ltd\.?|llc|inc\.?|bvba|vof|stichting|holding)\b/iu;

export type PartyKindChoice = "person" | "company" | "auto";

/** A name classified for a contacts import. */
export interface ClassifiedParty {
  readonly kind: "person" | "company";
  readonly displayName: string;
  readonly legalName: string;
  readonly given: string;
  readonly initials: string;
  readonly infix: string;
  readonly last: string;
}

/**
 * Classify a party name. `auto` treats a legal suffix as a company and keeps
 * initials on a person, so three Gerritsen rows stay different people.
 */
export function classifyParty(
  value: string,
  kind: PartyKindChoice = "auto",
): ClassifiedParty {
  const name = normalizeName(value);
  const person = splitPersonName(name);
  const business = BUSINESS_MARK.test(name);
  const decided = kind === "auto" ? (business ? "company" : "person") : kind;

  if (decided === "company") {
    return {
      kind: "company",
      displayName: name,
      legalName: name,
      given: "",
      initials: "",
      infix: "",
      last: "",
    };
  }

  const family = /\s(?:en|\/)\s/iu.test(name);

  return {
    kind: "person",
    displayName: family ? name : person.display,
    legalName: "",
    given: person.given,
    initials: person.initials,
    infix: person.infix,
    last: person.last,
  };
}

/** An E.164-shaped number. A national trunk `0` uses `defaultRegion`. */
export function normalizePhone(
  value: string,
  options: PhoneOptions = {},
): string {
  const compact = value.replaceAll(/[\s().-]/g, "");

  const international = compact.startsWith("00")
    ? `+${compact.slice(2)}`
    : compact;

  if (international.startsWith("+")) {
    return `+${international.slice(1).replaceAll(/\D/g, "")}`;
  }

  const digits = international.replaceAll(/\D/g, "");
  const region = options.defaultRegion?.toUpperCase();
  const calling = region === undefined ? undefined : CALLING[region];

  if (calling !== undefined && digits.startsWith("0")) {
    return `+${calling}${digits.slice(1)}`;
  }

  return calling === undefined ? digits : `+${calling}${digits}`;
}

/** Lower-case, trimmed address. */
export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

/** A postal code in the country's usual shape. Unknown countries are trimmed. */
export function normalizePostalCode(
  value: string,
  options: CountryOptions = {},
): string {
  const compact = value.trim().replaceAll(/\s+/g, " ").toUpperCase();
  const country = options.country?.toUpperCase();

  if (country === "NL") {
    const match = /^([1-9][0-9]{3})\s?([A-Z]{2})$/u.exec(
      compact.replaceAll(" ", ""),
    );

    return match ? `${match[1]} ${match[2]}` : compact;
  }

  if (country === "DE") {
    return compact.replaceAll(/\s/g, "");
  }

  if (country === "US") {
    const digits = compact.replaceAll(/[^\d-]/g, "");
    const nine = /^(\d{5})-?(\d{4})$/u.exec(digits);

    return nine ? `${nine[1]}-${nine[2]}` : digits;
  }

  return compact;
}

export interface StreetParts {
  readonly street: string;
  readonly number: string;
  readonly addition: string;
}

/** Split a street line into street, number and addition. */
export function splitStreet(
  value: string,
  options: CountryOptions = {},
): StreetParts {
  const line = value.trim().replaceAll(/\s+/g, " ");
  const country = options.country?.toUpperCase();

  const match =
    country === "NL" || country === "DE" || country === undefined
      ? /^(.*?)[\s,]+(\d+)\s*([-/\w]*)$/u.exec(line)
      : null;

  if (!match) {
    return { street: line, number: "", addition: "" };
  }

  return {
    street: match[1] ?? "",
    number: match[2] ?? "",
    addition: match[3] ?? "",
  };
}

/** ISO 13616 check: the rearranged number modulo 97 is 1. */
export function validateIban(value: string): boolean {
  const compact = value.replaceAll(/\s/g, "").toUpperCase();

  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/u.test(compact)) {
    return false;
  }

  const moved = compact.slice(4) + compact.slice(0, 4);
  let rest = 0;

  for (const char of moved) {
    const digits =
      char >= "A" && char <= "Z" ? String(char.codePointAt(0)! - 55) : char;

    for (const digit of digits) {
      rest = (rest * 10 + Number(digit)) % 97;
    }
  }

  return rest === 1;
}

/** An 8 or 11 character BIC, upper case, or an empty string when it is not one. */
export function normalizeBic(value: string): string {
  const compact = value.replaceAll(/\s/g, "").toUpperCase();

  return /^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$/u.test(compact)
    ? compact
    : "";
}

/**
 * A national identifier with spaces removed. `NL` keeps an 8 digit chamber of
 * commerce number and rejects anything else.
 */
export function normalizeNationalId(
  value: string,
  options: CountryOptions = {},
): string {
  const compact = value.replaceAll(/[\s.-]/g, "");
  const country = options.country?.toUpperCase();

  if (country === "NL") {
    return /^\d{8}$/u.test(compact) ? compact : "";
  }

  return compact;
}

function withoutControl(value: string): string {
  let out = "";

  for (const char of value) {
    const code = char.codePointAt(0) ?? 0;

    const control =
      code <= 8 ||
      code === 11 ||
      code === 12 ||
      (code >= 14 && code <= 31) ||
      code === 127;

    if (!control) {
      out += char;
    }
  }

  return out;
}

/**
 * Apply `repairs` once each, then optional CSV-quote and control stripping. A
 * repair whose replacement still contains its pattern is applied once, so the
 * function stays idempotent for the named packs.
 */
export function sanitizeText(
  value: string,
  options: SanitizeOptions = {},
): string {
  let text =
    options.repairs?.reduce(
      (current, repair) => replaceOnce(current, repair),
      value,
    ) ?? value;

  if (options.csvQuotes === true) {
    const wrapped = /^"(.*)"$/u.exec(text);
    text = wrapped ? (wrapped[1] ?? "") : text.replace(/^["'`]+/u, "");
  }

  if (options.stripControl === true) {
    text = withoutControl(text);
  }

  return text.replaceAll(/[ \t]{2,}/g, " ").trim();
}

/**
 * How much of `value` matches a named pack, from 0 to 1. Zero when no pack
 * pattern occurs.
 */
export function detectMojibake(value: string): number {
  const hits = Object.values(TEXT_PACKS).reduce(
    (count, pack) =>
      count +
      pack.filter(
        (repair) =>
          repair.pattern !== repair.replacement &&
          value.includes(repair.pattern),
      ).length,
    0,
  );

  return hits === 0 ? 0 : Math.min(1, hits / 4);
}

/** True when most words of three letters or more are all capitals. */
export function looksShouted(value: string): boolean {
  const words = value
    .split(/\s+/u)
    .filter((word) => word.replaceAll(/[^A-Za-z]/g, "").length >= 3);

  const shouted = words.filter((word) =>
    SHOUTED_WORD.test(word.replaceAll(/[^A-Za-z]/g, "")),
  );

  return words.length > 0 && shouted.length * 2 >= words.length;
}
