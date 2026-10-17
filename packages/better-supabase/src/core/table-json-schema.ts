import type { StandardSchemaV1 } from "@standard-schema/spec";

import { isList } from "./guards.ts";

/** Validator for one scalar, independent of the target library. */
export type ScalarKind =
  | { readonly kind: "uuid" }
  | { readonly kind: "string" }
  | { readonly kind: "integer" }
  | { readonly kind: "number" }
  | { readonly kind: "boolean" }
  | { readonly kind: "datetime" }
  | { readonly kind: "date" }
  | { readonly kind: "instant" }
  | { readonly kind: "plainDateTime" }
  | { readonly kind: "bigint" }
  | { readonly kind: "json" }
  | { readonly kind: "enum"; readonly values: readonly string[] }
  | { readonly kind: "unknown" };

export interface FieldOptions {
  readonly nullable?: boolean;
  /** The key may be left out. A present key never accepts `undefined`. */
  readonly optional?: boolean;
  readonly array?: boolean;
  /** Filled by a plugin (`timestamps()`, `actor()`, `softDelete()`). */
  readonly readOnly?: boolean;
  readonly description?: string;
  readonly examples?: readonly unknown[];
  readonly minimum?: number;
  readonly exclusiveMinimum?: number;
  readonly maximum?: number;
  readonly exclusiveMaximum?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
  /** Validates a typed jsonb column; its JSON Schema is used when it has one. */
  readonly schema?: StandardSchemaV1;
}

/**
 * One column of a table schema. `custom` is a jsonb column with a TypeScript
 * type from the config and no schema: any value except `undefined` passes.
 */
export type FieldSpec = (ScalarKind | { readonly kind: "custom" }) &
  FieldOptions;

export interface TableSchemaSpec {
  readonly title?: string;
  readonly description?: string;
  readonly fields: Readonly<Record<string, FieldSpec>>;
}

export type JsonSchema = Record<string, unknown>;

/** JSON Schema for one scalar. Codec values are described by their wire form. */
function scalarJsonSchema(
  kind: ScalarKind | { readonly kind: "custom" },
): JsonSchema {
  switch (kind.kind) {
    case "uuid": {
      return { type: "string", format: "uuid" };
    }
    case "string": {
      return { type: "string" };
    }
    case "integer": {
      return { type: "integer" };
    }
    case "number": {
      return { type: "number" };
    }
    case "boolean": {
      return { type: "boolean" };
    }
    case "datetime": {
      return { type: "string", format: "date-time" };
    }
    case "date": {
      return { type: "string", format: "date" };
    }
    case "instant": {
      return { type: "string", format: "date-time" };
    }
    case "plainDateTime": {
      return {
        type: "string",
        pattern: "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?$",
      };
    }
    case "bigint": {
      return { type: "string", pattern: "^-?\\d+$" };
    }
    case "json":
    case "unknown":
    case "custom": {
      return {};
    }
    case "enum": {
      return { type: "string", enum: [...kind.values] };
    }
    default: {
      const exhaustive: never = kind;
      return exhaustive;
    }
  }
}

/** Wraps a column's schema for arrays and `null`. */
function columnJsonSchema(
  base: JsonSchema,
  field: Pick<FieldOptions, "array" | "nullable">,
): JsonSchema {
  const schema = field.array ? { type: "array", items: base } : base;
  if (!field.nullable) {
    return schema;
  }
  if (Object.keys(schema).length === 0) {
    return schema;
  }
  const { enum: values, ...rest } = schema;
  if (isList(values)) {
    return { ...rest, type: ["string", "null"], enum: [...values, null] };
  }
  return typeof schema["type"] === "string"
    ? { ...schema, type: [schema["type"], "null"] }
    : { anyOf: [schema, { type: "null" }] };
}

const BOUND_KEYS = [
  "minimum",
  "exclusiveMinimum",
  "maximum",
  "exclusiveMaximum",
  "minLength",
  "maxLength",
] as const;

function propertySchema(field: FieldSpec, base: JsonSchema): JsonSchema {
  const bounds: JsonSchema = {};
  for (const key of BOUND_KEYS) {
    const value = field[key];
    if (value !== undefined) {
      bounds[key] = value;
    }
  }
  const schema = {
    ...columnJsonSchema({ ...base, ...bounds }, field),
    ...(field.description === undefined
      ? {}
      : { description: field.description }),
    ...(field.examples === undefined ? {} : { examples: [...field.examples] }),
  };
  return field.readOnly ? { ...schema, readOnly: true } : schema;
}

/**
 * The JSON Schema object for a table shape. `nested` converts a typed jsonb
 * column's own schema; without it those columns accept any value.
 */
export function tableJsonSchema(
  spec: TableSchemaSpec,
  nested?: (schema: StandardSchemaV1) => JsonSchema | undefined,
): JsonSchema {
  const properties: Record<string, JsonSchema> = {};
  const required: string[] = [];
  for (const [name, field] of Object.entries(spec.fields)) {
    const base =
      (field.schema && nested?.(field.schema)) ?? scalarJsonSchema(field);
    properties[name] = propertySchema(field, base);
    if (!field.optional) {
      required.push(name);
    }
  }
  return {
    ...(spec.title === undefined ? {} : { title: spec.title }),
    ...(spec.description === undefined
      ? {}
      : { description: spec.description }),
    type: "object",
    properties,
    ...(required.length > 0 ? { required } : {}),
    additionalProperties: false,
  };
}
