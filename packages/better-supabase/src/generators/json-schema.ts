import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import { isList } from "../core/guards.ts";
import {
  type DocsSource,
  type FieldDocs,
  fieldDocs,
  type FieldPlan,
  fieldsFor,
  type ScalarKind,
  siblingPath,
  tableDocs,
  tableEntries,
  variantsFor,
  variantTitle,
} from "./shared.ts";

export interface JsonSchemaGeneratorOptions {
  /** Output path relative to the project root. Defaults to `<output>.schema.json`. */
  readonly output?: string;
  /** `$id` of the document. */
  readonly id?: string;
}

type JsonSchema = Record<string, unknown>;

function scalar(kind: ScalarKind): JsonSchema {
  switch (kind.kind) {
    case "uuid":
      return { type: "string", format: "uuid" };
    case "string":
      return { type: "string" };
    case "integer":
      return { type: "integer" };
    case "number":
      return { type: "number" };
    case "boolean":
      return { type: "boolean" };
    case "datetime":
      return { type: "string", format: "date-time" };
    case "date":
      return { type: "string", format: "date" };
    case "instant":
      return { type: "string", format: "date-time" };
    case "plainDateTime":
      return {
        type: "string",
        pattern: "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?$",
      };
    case "bigint":
      return { type: "string", pattern: "^-?\\d+$" };
    case "json":
    case "unknown":
      return {};
    case "enum":
      return { type: "string", enum: [...kind.values] };
    default: {
      const exhaustive: never = kind;
      return exhaustive;
    }
  }
}

function property(plan: FieldPlan, docs: FieldDocs): JsonSchema {
  const { description, examples, ...bounds } = docs;
  const schema = {
    ...nullable(plan, bounds),
    ...(description === undefined ? {} : { description }),
    ...(examples === undefined ? {} : { examples: [...examples] }),
  };
  return plan.managed ? { ...schema, readOnly: true } : schema;
}

function nullable(plan: FieldPlan, bounds: JsonSchema): JsonSchema {
  let schema = { ...scalar(plan.scalar), ...bounds };
  if (plan.column.array) schema = { type: "array", items: schema };
  if (!plan.nullable) return schema;
  if (Object.keys(schema).length === 0) return schema;
  const { enum: values, ...rest } = schema;
  if (isList(values))
    return { ...rest, type: ["string", "null"], enum: [...values, null] };
  return typeof schema["type"] === "string"
    ? { ...schema, type: [schema["type"], "null"] }
    : { anyOf: [schema, { type: "null" }] };
}

/** JSON Schema (2020-12) `$defs` for every table: `customersRow`, `customersInsert`, ... */
export function buildJsonSchema(input: DocsSource, id?: string): JsonSchema {
  const defs: Record<string, JsonSchema> = {};
  for (const [key, table] of tableEntries(input)) {
    const docs = tableDocs(input, table);
    for (const variant of variantsFor(table)) {
      const properties: Record<string, JsonSchema> = {};
      const required: string[] = [];
      for (const plan of fieldsFor(table, variant, input)) {
        properties[plan.name] = property(plan, fieldDocs(docs, plan));
        if (!plan.optional) required.push(plan.name);
      }
      defs[`${key}${variant}`] = {
        ...(docs
          ? {
              title: variantTitle(docs, variant),
              ...(docs.description === undefined
                ? {}
                : { description: docs.description }),
            }
          : {}),
        type: "object",
        properties,
        ...(required.length > 0 ? { required } : {}),
        additionalProperties: false,
      };
    }
  }
  return {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    ...(id ? { $id: id } : {}),
    $defs: defs,
  };
}

/** Writes the JSON Schema document; `createOpenApi` reuses the same `$defs`. */
export function jsonSchema(
  options: JsonSchemaGeneratorOptions = {},
): Generator {
  return {
    name: "json-schema",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "schema.json");
      return [
        {
          path,
          contents: `${JSON.stringify(buildJsonSchema(input, options.id), null, 2)}\n`,
        },
      ];
    },
  };
}
