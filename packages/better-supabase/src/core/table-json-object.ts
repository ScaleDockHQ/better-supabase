import type { StandardSchemaV1 } from "@standard-schema/spec";

import type {
  FieldSpec,
  JsonSchema,
  TableSchemaSpec,
} from "./table-json-schema.ts";

import { isList, isRecord } from "./guards.ts";

type ScalarField = Exclude<FieldSpec, { readonly kind: "object" }>;

// Copied from table-json-schema.ts. This module is only reached from the
// client through the public table walker, which pages do not import. Importing
// the helpers would export them from the client schema chunk.
function scalarJsonSchema(kind: ScalarField): JsonSchema {
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

    case "plainDate": {
      return { type: "string", format: "date" };
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

function columnJsonSchema(
  base: JsonSchema,
  field: Pick<FieldSpec, "array" | "nullable">,
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

type ObjectField = Extract<FieldSpec, { readonly kind: "object" }>;

/**
 * A nested Standard Schema's JSON Schema, without its dialect URI. Absent when
 * the schema does not implement Standard JSON Schema.
 */
function nestedJson(field: FieldSpec): JsonSchema | undefined {
  const schema = field.schema;

  if (!schema) {
    return undefined;
  }

  const standard = schema["~standard"];

  if (!("jsonSchema" in standard) || !isRecord(standard.jsonSchema)) {
    return undefined;
  }

  const output = standard.jsonSchema["output"];

  if (typeof output !== "function") {
    return undefined;
  }

  // SAFETY: the typeof check above proves output is a function.
  const convert = output as (options: { readonly target: string }) => unknown;

  const produced: unknown = convert({ target: "draft-2020-12" });

  if (!isRecord(produced)) {
    return undefined;
  }

  const rest: JsonSchema = { ...produced };

  Reflect.deleteProperty(rest, "$schema");

  return rest;
}

/** JSON Schema for a composite object, including each nested field. */
export function objectJsonSchema(field: ObjectField): JsonSchema {
  const properties: Record<string, JsonSchema> = {};
  const required: string[] = [];

  for (const [name, nested] of Object.entries(field.fields)) {
    properties[name] = fieldJsonSchema(nested);

    if (!nested.optional) {
      required.push(name);
    }
  }

  return {
    type: "object",
    properties,
    additionalProperties: false,
    ...(required.length > 0 ? { required } : {}),
  };
}

/**
 * The JSON Schema object for a table shape that may contain composite fields.
 * `nested` converts a typed jsonb column's own schema.
 */
export function compositeTableJsonSchema(
  spec: TableSchemaSpec,
  nested?: (schema: StandardSchemaV1) => JsonSchema | undefined,
): JsonSchema {
  const properties: Record<string, JsonSchema> = {};
  const required: string[] = [];

  for (const [name, field] of Object.entries(spec.fields)) {
    const fromSchema = field.schema ? nested?.(field.schema) : undefined;

    const base =
      fromSchema ??
      (field.kind === "object"
        ? objectJsonSchema(field)
        : scalarJsonSchema(field));

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

/** The JSON Schema for one field, with its array, null, bounds and docs. */
export function fieldJsonSchema(field: FieldSpec): JsonSchema {
  const base =
    nestedJson(field) ??
    (field.kind === "object"
      ? objectJsonSchema(field)
      : scalarJsonSchema(field));

  return propertySchema(field, base);
}
