import type {
  StandardJSONSchemaV1,
  StandardSchemaV1,
} from "@standard-schema/spec";

import { isList } from "./guards.ts";
import {
  type FieldSpec,
  type JsonSchema,
  tableJsonSchema,
  type TableSchemaSpec,
} from "./table-json-schema.ts";
import { isInstant, isPlainDateTime } from "./temporal.ts";

export type { StandardJSONSchemaV1 };
export type { FieldSpec, TableSchemaSpec } from "./table-json-schema.ts";

/** A Standard Schema that also converts to JSON Schema (Standard JSON Schema). */
export interface TableSchema<T> {
  readonly "~standard": StandardSchemaV1.Props<T, T> &
    StandardJSONSchemaV1.Props<T, T>;
}

const SCHEMA_URIS: Readonly<Record<string, string>> = {
  "draft-2020-12": "https://json-schema.org/draft/2020-12/schema",
  "draft-07": "http://json-schema.org/draft-07/schema#",
};

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !isList(value);
}

/** Rewrites a 2020-12 schema into the OpenAPI 3.0 dialect (`nullable`, `example`). */
function toOpenApi30(schema: JsonSchema): JsonSchema {
  const out: JsonSchema = {};
  for (const [key, value] of Object.entries(schema)) {
    if (key === "properties" && isObject(value)) {
      out[key] = Object.fromEntries(
        Object.entries(value).map(([name, child]) => [
          name,
          isObject(child) ? toOpenApi30(child) : child,
        ]),
      );
    } else if (key === "items" && isObject(value)) {
      out[key] = toOpenApi30(value);
    } else if (key === "examples" && isList(value)) {
      if (value.length > 0) out["example"] = value[0];
    } else if (key === "exclusiveMinimum" || key === "exclusiveMaximum") {
      out[key === "exclusiveMinimum" ? "minimum" : "maximum"] = value;
      out[key] = true;
    } else {
      out[key] = value;
    }
  }
  const type = out["type"];
  if (isList(type) && type.includes("null")) {
    out["type"] = type.find((entry) => entry !== "null");
    out["nullable"] = true;
  }
  const anyOf = out["anyOf"];
  if (isList(anyOf) && anyOf.length === 2) {
    const [inner, empty] = anyOf;
    if (isObject(inner) && isObject(empty) && empty["type"] === "null") {
      delete out["anyOf"];
      return { ...toOpenApi30(inner), ...out, nullable: true };
    }
  }
  return out;
}

/** The schema with the target's `$schema`, or in the OpenAPI 3.0 dialect. */
function forTarget(
  schema: JsonSchema,
  target: StandardJSONSchemaV1.Target,
): JsonSchema {
  if (target === "openapi-3.0") return toOpenApi30(schema);
  const uri = SCHEMA_URIS[target];
  if (!uri) throw new Error(`Unsupported JSON Schema target "${target}"`);
  return { $schema: uri, ...schema };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const DATETIME =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}(?::?\d{2})?)$/;

function isJson(value: unknown): boolean {
  if (value === null || typeof value === "string" || typeof value === "boolean")
    return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (isList(value)) return value.every(isJson);
  if (!isObject(value)) return false;
  const proto: unknown = Object.getPrototypeOf(value);
  return (
    (proto === Object.prototype || proto === null) &&
    Object.values(value).every(isJson)
  );
}

/** The issue message for a scalar, or `undefined` when the value passes. */
function scalarIssue(field: FieldSpec, value: unknown): string | undefined {
  switch (field.kind) {
    case "uuid":
      return typeof value === "string" && UUID.test(value)
        ? undefined
        : "Expected a UUID";
    case "string":
      return typeof value === "string" ? undefined : "Expected a string";
    case "integer":
      return Number.isSafeInteger(value) ? undefined : "Expected an integer";
    case "number":
      return typeof value === "number" && Number.isFinite(value)
        ? undefined
        : "Expected a number";
    case "boolean":
      return typeof value === "boolean" ? undefined : "Expected a boolean";
    case "datetime":
      return typeof value === "string" && DATETIME.test(value)
        ? undefined
        : "Expected an ISO 8601 date-time with an offset";
    case "date":
      return typeof value === "string" && DATE.test(value)
        ? undefined
        : "Expected an ISO 8601 date";
    case "instant":
      return isInstant(value) ? undefined : "Expected a Temporal.Instant";
    case "plainDateTime":
      return isPlainDateTime(value)
        ? undefined
        : "Expected a Temporal.PlainDateTime";
    case "bigint":
      return typeof value === "bigint" ? undefined : "Expected a bigint";
    case "json":
      return isJson(value) ? undefined : "Expected a JSON value";
    case "enum":
      return typeof value === "string" && field.values.includes(value)
        ? undefined
        : `Expected one of ${field.values.map((entry) => JSON.stringify(entry)).join(", ")}`;
    case "unknown":
      return undefined;
    case "custom":
      return value === undefined ? "Expected a value" : undefined;
    default: {
      const exhaustive: never = field;
      return exhaustive;
    }
  }
}

const characters = (count: number): string =>
  count === 1 ? "1 character" : `${count} characters`;

function boundIssue(field: FieldSpec, value: unknown): string | undefined {
  if (typeof value === "number") {
    if (field.minimum !== undefined && value < field.minimum)
      return `Expected at least ${field.minimum}`;
    if (field.exclusiveMinimum !== undefined && value <= field.exclusiveMinimum)
      return `Expected more than ${field.exclusiveMinimum}`;
    if (field.maximum !== undefined && value > field.maximum)
      return `Expected at most ${field.maximum}`;
    if (field.exclusiveMaximum !== undefined && value >= field.exclusiveMaximum)
      return `Expected less than ${field.exclusiveMaximum}`;
  }
  if (typeof value === "string") {
    if (field.minLength !== undefined && value.length < field.minLength)
      return `Expected at least ${characters(field.minLength)}`;
    if (field.maxLength !== undefined && value.length > field.maxLength)
      return `Expected at most ${characters(field.maxLength)}`;
  }
  return undefined;
}

type Issues = StandardSchemaV1.Issue[];

function nestedIssues(
  result: StandardSchemaV1.Result<unknown>,
  path: readonly PropertyKey[],
): Issues {
  return (result.issues ?? []).map((issue) => ({
    message: issue.message,
    path: [...path, ...(issue.path ?? [])],
  }));
}

/** Checks one element; a nested schema's async result lands in `pending`. */
function checkValue(
  field: FieldSpec,
  value: unknown,
  path: readonly PropertyKey[],
  issues: Issues,
  pending: Promise<Issues>[],
): void {
  if (field.schema) {
    const result = field.schema["~standard"].validate(value);
    if (result instanceof Promise)
      pending.push(result.then((settled) => nestedIssues(settled, path)));
    else issues.push(...nestedIssues(result, path));
    return;
  }
  const message = scalarIssue(field, value) ?? boundIssue(field, value);
  if (message) issues.push({ message, path: [...path] });
}

function checkField(
  name: string,
  field: FieldSpec,
  value: unknown,
  issues: Issues,
  pending: Promise<Issues>[],
): void {
  if (value === null && field.nullable) return;
  if (!field.array) {
    checkValue(field, value, [name], issues, pending);
    return;
  }
  if (!isList(value)) {
    issues.push({ message: "Expected an array", path: [name] });
    return;
  }
  value.forEach((item, index) => {
    checkValue(field, item, [name, index], issues, pending);
  });
}

/**
 * A Standard Schema for one table shape, without a validation library. It
 * validates like the `zod()` and `valibot()` output, drops unknown keys, and
 * converts to JSON Schema for `draft-2020-12`, `draft-07` and `openapi-3.0`.
 * The `standardSchema()` generator emits one per Row, Insert and Update.
 */
export function tableSchema<T>(spec: TableSchemaSpec): TableSchema<T> {
  const entries = Object.entries(spec.fields);
  const validate = (
    input: unknown,
  ): StandardSchemaV1.Result<T> | Promise<StandardSchemaV1.Result<T>> => {
    if (!isObject(input))
      return { issues: [{ message: "Expected an object" }] };
    const issues: Issues = [];
    const pending: Promise<Issues>[] = [];
    const value: Record<string, unknown> = {};
    for (const [name, field] of entries) {
      if (!Object.hasOwn(input, name)) {
        if (!field.optional && field.kind !== "unknown")
          issues.push({ message: "Required", path: [name] });
        continue;
      }
      value[name] = input[name];
      checkField(name, field, input[name], issues, pending);
    }
    const settle = (all: Issues): StandardSchemaV1.Result<T> =>
      // SAFETY: every known key passed its column check and unknown keys were
      // dropped, so the object has the shape of T.
      all.length > 0 ? { issues: all } : { value: value as T };
    if (pending.length === 0) return settle(issues);
    return Promise.all(pending).then((nested) =>
      settle([...issues, ...nested.flat()]),
    );
  };
  const convert =
    (direction: "input" | "output") =>
    (options: StandardJSONSchemaV1.Options): JsonSchema =>
      forTarget(
        tableJsonSchema(spec, (schema) => {
          const standard: Partial<StandardJSONSchemaV1.Props> =
            schema["~standard"];
          const converted = standard.jsonSchema?.[direction](options);
          if (!converted) return converted;
          const { $schema: _, ...rest } = converted;
          return rest;
        }),
        options.target,
      );
  return {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate,
      jsonSchema: { input: convert("input"), output: convert("output") },
    },
  };
}
