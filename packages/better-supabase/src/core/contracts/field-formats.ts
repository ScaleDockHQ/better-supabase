import type { FormFieldType } from "./form-definition.ts";

/**
 * The one field vocabulary: the formats an app table column takes and the types
 * a custom field takes. App tables render each format's check from here, and
 * the forms block answers a custom field with the form field type it maps to.
 */

/** The Postgres column types a format fits. */
export type FieldFormatColumnType = "text" | "integer" | "bigint" | "numeric";

/** The HTML input a format edits with. */
export type FieldFormatInput =
  | "text"
  | "email"
  | "url"
  | "tel"
  | "textarea"
  | "color"
  | "number";

/**
 * A check a pattern can't express, run by the SQL function
 * `bsb_valid_<name>(text)`: `bsn` is the Dutch citizen service number (9 digits
 * that pass the elfproef), `iban` an ISO 13616 account number in its electronic
 * form (uppercase, no spaces) whose mod 97 check is 1.
 */
export const FIELD_FORMAT_VALIDATORS = ["bsn", "iban"] as const;

export type FieldFormatValidator = (typeof FIELD_FORMAT_VALIDATORS)[number];

export interface FieldFormat {
  readonly types: readonly FieldFormatColumnType[];
  /** A POSIX regular expression the value matches, ignoring case. */
  readonly pattern?: string;
  /** The SQL check function the value passes. */
  readonly validator?: FieldFormatValidator;
  /** The bounds when the column sets no `min` or `max`. */
  readonly bounds?: readonly [min: number, max: number];
  readonly input: FieldFormatInput;
  /** The forms block field type that collects the value. */
  readonly formType: FormFieldType;
}

export const FIELD_FORMAT_NAMES = [
  "email",
  "url",
  "phone",
  "phone_e164",
  "long_text",
  "color",
  "rating",
  "percent",
  "currency",
  "bsn",
  "iban",
] as const;

export type FieldFormatName = (typeof FIELD_FORMAT_NAMES)[number];

/** The stars a `rating` takes, for a column and for a custom field. */
export const RATING_BOUNDS: readonly [min: number, max: number] = [1, 5];

const EMAIL = String.raw`^[^@\s]+@[^@\s]+\.[^@\s]+$`;
const URL = String.raw`^https?://\S+$`;

/**
 * ITU-T E.164: a plus, a country code that doesn't start with 0, 15 digits at
 * most.
 */
const E164 = String.raw`^\+[1-9][0-9]{1,14}$`;

/**
 * Money is a `currency` `bigint` of minor units next to a `text` column of 3
 * characters for the code (ADR 0037).
 */
export const FIELD_FORMATS: Readonly<Record<FieldFormatName, FieldFormat>> = {
  email: { types: ["text"], pattern: EMAIL, input: "email", formType: "email" },
  url: { types: ["text"], pattern: URL, input: "url", formType: "url" },
  phone: { types: ["text"], input: "tel", formType: "text" },
  phone_e164: {
    types: ["text"],
    pattern: E164,
    input: "tel",
    formType: "text",
  },
  long_text: { types: ["text"], input: "textarea", formType: "textarea" },
  color: { types: ["text"], input: "color", formType: "text" },
  rating: {
    types: ["integer", "bigint"],
    bounds: RATING_BOUNDS,
    input: "number",
    formType: "integer",
  },
  percent: {
    types: ["integer", "numeric"],
    bounds: [0, 100],
    input: "number",
    formType: "number",
  },
  currency: { types: ["bigint"], input: "number", formType: "integer" },
  bsn: { types: ["text"], validator: "bsn", input: "text", formType: "text" },
  iban: { types: ["text"], validator: "iban", input: "text", formType: "text" },
};

/**
 * The types of a custom field definition. A value is stored as text either way;
 * the type tells the form and the UI what it holds. `user` holds a user id,
 * `currency` an integer of minor units, and `multi_option` a JSON array of
 * option values.
 */
export const CUSTOM_FIELD_TYPES = [
  "text",
  "number",
  "date",
  "bool",
  "option",
  "json",
  "email",
  "url",
  "multi_option",
  "user",
  "rating",
  "currency",
  "bsn",
  "iban",
  "phone_e164",
] as const;

export type CustomFieldType = (typeof CUSTOM_FIELD_TYPES)[number];

/**
 * The custom field types whose values the database checks against the format of
 * the same name before it stores them.
 */
export const CUSTOM_FIELD_CHECKED_FORMATS: Readonly<
  Partial<Record<CustomFieldType, FieldFormatName>>
> = { bsn: "bsn", iban: "iban", phone_e164: "phone_e164" };

/** The forms block field type that answers each custom field type. */
export const CUSTOM_FIELD_FORM_TYPES: Readonly<
  Record<CustomFieldType, FormFieldType>
> = {
  text: "text",
  number: "number",
  date: "date",
  bool: "bool",
  option: "option",
  json: "json",
  email: FIELD_FORMATS.email.formType,
  url: FIELD_FORMATS.url.formType,
  multi_option: "multi",
  user: "text",
  rating: FIELD_FORMATS.rating.formType,
  currency: FIELD_FORMATS.currency.formType,
  bsn: FIELD_FORMATS.bsn.formType,
  iban: FIELD_FORMATS.iban.formType,
  phone_e164: FIELD_FORMATS.phone_e164.formType,
};
