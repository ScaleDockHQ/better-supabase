import type { FormFieldType } from "./form-definition.ts";

/**
 * The one field vocabulary: the formats an app table column takes and the types
 * a custom field takes. App tables render each format's check from here,
 * `scaffold screens` picks the input, and the forms block answers a custom
 * field with the form field type it maps to.
 */

/** The Postgres column types a format fits. */
export type FieldFormatColumnType = "text" | "integer" | "bigint" | "numeric";

/** The HTML input a format edits with. */
export type FieldFormatInput =
  | "email"
  | "url"
  | "tel"
  | "textarea"
  | "color"
  | "number";

export interface FieldFormat {
  readonly types: readonly FieldFormatColumnType[];
  /** A POSIX regular expression the value matches, ignoring case. */
  readonly pattern?: string;
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
  "long_text",
  "color",
  "rating",
  "percent",
  "currency",
] as const;

export type FieldFormatName = (typeof FIELD_FORMAT_NAMES)[number];

/** The stars a `rating` takes, for a column and for a custom field. */
export const RATING_BOUNDS: readonly [min: number, max: number] = [1, 5];

const EMAIL = String.raw`^[^@\s]+@[^@\s]+\.[^@\s]+$`;
const URL = String.raw`^https?://\S+$`;

/**
 * Money is a `currency` `bigint` of minor units next to a `text` column of 3
 * characters for the code (ADR 0037).
 */
export const FIELD_FORMATS: Readonly<Record<FieldFormatName, FieldFormat>> = {
  email: { types: ["text"], pattern: EMAIL, input: "email", formType: "email" },
  url: { types: ["text"], pattern: URL, input: "url", formType: "url" },
  phone: { types: ["text"], input: "tel", formType: "text" },
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
] as const;

export type CustomFieldType = (typeof CUSTOM_FIELD_TYPES)[number];

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
};
