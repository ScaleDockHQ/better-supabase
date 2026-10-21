import type { StandardSchemaV1 } from "@standard-schema/spec";

import type {
  FormJson,
  FormJsonSchema,
} from "../../core/contracts/form-definition.ts";
import type { ValidationIssue } from "../../core/errors.ts";

/** A submission's answers, by field key. */
export type FormAnswers = { readonly [key: string]: FormJson };

/**
 * `email` as the HTML `<input type="email">` grammar, `date` as RFC 3339
 * `full-date`. Postgres asserts the same formats, so a value this accepts can
 * still fail there only for a mailbox the HTML grammar allows and pg_jsonschema
 * does not.
 */
const EMAIL =
  /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/;

const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const URI_SCHEME = /^[a-zA-Z][a-zA-Z0-9+.-]*:/;

function isObject(
  value: unknown,
): value is { readonly [key: string]: unknown } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function schemaOf(value: unknown): FormJsonSchema {
  // SAFETY: a FormJsonSchema is a JSON object; isObject checked the shape.
  return isObject(value) ? (value as FormJsonSchema) : {};
}

function typeMatches(type: unknown, value: unknown): boolean {
  switch (type) {
    case "string": {
      return typeof value === "string";
    }

    case "number": {
      return typeof value === "number" && Number.isFinite(value);
    }

    case "integer": {
      return typeof value === "number" && Number.isInteger(value);
    }

    case "boolean": {
      return typeof value === "boolean";
    }

    case "array": {
      return Array.isArray(value);
    }

    case "object": {
      return isObject(value);
    }

    case "null": {
      return value === null;
    }

    default: {
      return true;
    }
  }
}

function equal(a: unknown, b: unknown): boolean {
  if (a === b) {
    return true;
  }

  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((item, i) => equal(item, b[i]));
  }

  if (isObject(a) && isObject(b)) {
    const keys = Object.keys(a);

    return (
      keys.length === Object.keys(b).length &&
      keys.every((key) => key in b && equal(a[key], b[key]))
    );
  }

  return false;
}

function validDate(value: string): boolean {
  const match = DATE.exec(value);

  if (match === null) {
    return false;
  }

  const [year, month, day] = [
    Number(match[1]),
    Number(match[2]),
    Number(match[3]),
  ];

  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();

  return month >= 1 && month <= 12 && day >= 1 && day <= last;
}

function formatMatches(format: unknown, value: string): boolean {
  switch (format) {
    case "email": {
      return EMAIL.test(value);
    }

    case "date": {
      return validDate(value);
    }

    case "uri": {
      return URI_SCHEME.test(value) && URL.canParse(value);
    }

    default: {
      return true;
    }
  }
}

const SURROGATE_PAIR = /[\uD800-\uDBFF][\uDC00-\uDFFF]/g;

/** Code points, as JSON Schema counts string length. */
const lengthOf = (value: string): number =>
  value.length - (value.match(SURROGATE_PAIR)?.length ?? 0);

const items = (count: number): string =>
  count === 1 ? "1 item" : `${count} items`;

function check(
  schema: FormJsonSchema,
  value: unknown,
  path: readonly PropertyKey[],
  issues: ValidationIssue[],
): void {
  const at = (message: string) => issues.push({ message, path });

  if ("type" in schema && !typeMatches(schema["type"], value)) {
    at(`must be ${String(schema["type"])}`);

    return;
  }

  if ("const" in schema && !equal(schema["const"], value)) {
    at(`must be ${JSON.stringify(schema["const"])}`);
  }

  const allowed = schema["enum"];

  if (Array.isArray(allowed) && !allowed.some((item) => equal(item, value))) {
    at("must be one of the options");
  }

  if ("not" in schema) {
    const inner: ValidationIssue[] = [];
    check(schemaOf(schema["not"]), value, path, inner);

    if (inner.length === 0) {
      at("is required");
    }
  }

  if (typeof value === "string") {
    const { minLength, maxLength, pattern, format } = schema;

    if (typeof minLength === "number" && lengthOf(value) < minLength) {
      at(
        minLength === 1
          ? "is required"
          : `must be at least ${minLength} characters`,
      );
    }

    if (typeof maxLength === "number" && lengthOf(value) > maxLength) {
      at(`must be at most ${maxLength} characters`);
    }

    if (typeof pattern === "string" && !new RegExp(pattern, "u").test(value)) {
      at("has the wrong format");
    }

    if (format !== undefined && !formatMatches(format, value)) {
      at(`must be a valid ${String(format)}`);
    }
  }

  if (typeof value === "number") {
    const { minimum, maximum } = schema;

    if (typeof minimum === "number" && value < minimum) {
      at(`must be at least ${minimum}`);
    }

    if (typeof maximum === "number" && value > maximum) {
      at(`must be at most ${maximum}`);
    }
  }

  if (Array.isArray(value)) {
    const { minItems, maxItems, uniqueItems } = schema;
    const each = schema["items"];

    if (typeof minItems === "number" && value.length < minItems) {
      at(`must have at least ${items(minItems)}`);
    }

    if (typeof maxItems === "number" && value.length > maxItems) {
      at(`must have at most ${items(maxItems)}`);
    }

    if (
      uniqueItems === true &&
      value.some(
        (item, i) => value.findIndex((other) => equal(item, other)) !== i,
      )
    ) {
      at("must not repeat an item");
    }

    if (each !== undefined) {
      value.forEach((item, i) => {
        check(schemaOf(each), item, [...path, i], issues);
      });
    }
  }

  if (isObject(value)) {
    const properties = schemaOf(schema["properties"]);
    const required = schema["required"];

    if (Array.isArray(required)) {
      for (const key of required) {
        if (typeof key === "string" && !(key in value)) {
          issues.push({ message: "is required", path: [...path, key] });
        }
      }
    }

    for (const [key, item] of Object.entries(value)) {
      if (key in properties) {
        check(schemaOf(properties[key]), item, [...path, key], issues);
      } else if (schema["additionalProperties"] === false) {
        issues.push({
          message: "is not a field of this form",
          path: [...path, key],
        });
      }
    }
  }

  const all = schema["allOf"];

  if (Array.isArray(all)) {
    for (const part of all) {
      check(schemaOf(part), value, path, issues);
    }
  }

  if ("if" in schema) {
    const condition: ValidationIssue[] = [];
    check(schemaOf(schema["if"]), value, path, condition);

    if (condition.length === 0 && "then" in schema) {
      check(schemaOf(schema["then"]), value, path, issues);
    }
  }
}

/**
 * Checks answers against a form version's schema with the keywords the
 * generator emits, so a form can show errors before it submits. Postgres checks
 * the same schema again on submit; this is not a general JSON Schema
 * validator.
 */
export function validateAnswers(
  schema: FormJsonSchema,
  answers: unknown,
): readonly ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  check(schema, answers, [], issues);

  return issues;
}

/** A form version's schema as a Standard Schema, for form libraries. */
export function answersSchema(
  schema: FormJsonSchema,
): StandardSchemaV1<unknown, FormAnswers> {
  return {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate: (value) => {
        const issues = validateAnswers(schema, value);

        // SAFETY: validateAnswers accepted the value as the schema's object.
        return issues.length === 0
          ? { value: value as FormAnswers }
          : { issues };
      },
    },
  };
}
