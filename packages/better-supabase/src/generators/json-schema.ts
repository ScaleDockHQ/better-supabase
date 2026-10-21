import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";
import type { ExtraSchemas, FieldMeta, ResultSchema } from "./extras.ts";
import type { JsonSchemaTarget } from "./json-schema-target.ts";
import type { DocsSource } from "./shared.ts";

import { fieldJsonSchema, tableJsonSchema } from "../core/table-json-schema.ts";
import { forTarget } from "../core/table-schema.ts";
import { extraSchemas, fieldMeta } from "./extras.ts";
import { toDraft07 } from "./json-schema-target.ts";
import {
  fieldDocs,
  fieldSpec,
  fieldsFor,
  siblingPath,
  tableDocs,
  tableEntries,
  variantsFor,
  variantTitle,
} from "./shared.ts";

export type { JsonSchemaTarget } from "./json-schema-target.ts";

export interface JsonSchemaGeneratorOptions {
  /**
   * Output path relative to the project root. Defaults to
   * `<output>.schema.json`.
   */
  readonly output?: string;
  /** `$id` of the document. */
  readonly id?: string;
  /**
   * The dialect. `draft-2020-12` (the default) writes `$defs`; `draft-07` and
   * `openapi-3.0` (`nullable`, `example`) write `definitions`.
   */
  readonly target?: JsonSchemaTarget;
  /**
   * Give each writable field a `title` label (from a short column comment or
   * its name), for form builders that read JSON Schema.
   */
  readonly fieldMeta?: boolean;
}

type JsonSchema = Record<string, unknown>;

const NO_EXTRAS: ExtraSchemas = { inputs: [], results: [] };

/** Marks the deprecated table and columns, which only `meta` knows about. */
function withDeprecated(
  schema: JsonSchema,
  deprecated: boolean,
  columns: readonly string[],
): JsonSchema {
  if (!deprecated && columns.length === 0) {
    return schema;
  }

  const properties = schema["properties"];

  return {
    ...schema,
    ...(deprecated ? { deprecated: true } : {}),
    ...(columns.length > 0 && typeof properties === "object" && properties
      ? {
          properties: Object.fromEntries(
            Object.entries(properties).map(
              ([name, value]: [string, unknown]) => [
                name,
                columns.includes(name) && typeof value === "object" && value
                  ? { ...value, deprecated: true }
                  : value,
              ],
            ),
          ),
        }
      : {}),
  };
}

function resultJsonSchema(
  result: ResultSchema,
  defs: Readonly<Record<string, JsonSchema>>,
  prefix: string,
): JsonSchema | undefined {
  if (result.of.kind === "row") {
    const row = `${result.of.table}Row`;

    if (defs[row] === undefined) {
      return undefined;
    }

    const ref = { $ref: `${prefix}${row}` };

    return {
      title: result.title,
      ...(result.set
        ? { type: "array", items: ref }
        : { anyOf: [ref, { type: "null" }] }),
    };
  }

  return {
    title: result.title,
    ...fieldJsonSchema({
      ...result.of.scalar,
      array: result.set,
      nullable: result.nullable && !result.set,
    }),
    ...(result.set && result.nullable
      ? { items: fieldJsonSchema({ ...result.of.scalar, nullable: true }) }
      : {}),
  };
}

/** Each field's `fieldMeta` label as its `title`. */
function withLabels(
  schema: JsonSchema,
  labels: Readonly<Record<string, FieldMeta>> | undefined,
): JsonSchema {
  const properties = schema["properties"];

  if (!labels || typeof properties !== "object" || !properties) {
    return schema;
  }

  return {
    ...schema,
    properties: Object.fromEntries(
      Object.entries(properties).map(([name, value]: [string, unknown]) => {
        const label = labels[name]?.label;

        return [
          name,
          label !== undefined && typeof value === "object" && value
            ? { title: label, ...value }
            : value,
        ];
      }),
    ),
  };
}

/**
 * JSON Schema `$defs` for every table: `customersRow`, `customersInsert`, ...
 * `target` lowers the document to draft-07 or the OpenAPI 3.0 dialect, which
 * keep the schemas under `definitions`.
 */
export function buildJsonSchema(
  input: DocsSource,
  id?: string,
  target: JsonSchemaTarget = "draft-2020-12",
  extras: ExtraSchemas = NO_EXTRAS,
): JsonSchema {
  const defs: Record<string, JsonSchema> = {};

  for (const [key, table] of tableEntries(input)) {
    const docs = tableDocs(input, table);
    const description = docs ? docs.description : table.description;

    for (const variant of variantsFor(table)) {
      const plans = fieldsFor(table, variant, input);

      const schema = tableJsonSchema({
        ...(docs ? { title: variantTitle(docs, variant) } : {}),
        ...(description === undefined ? {} : { description }),
        fields: Object.fromEntries(
          plans.map((plan) => {
            const spec = fieldSpec(plan, fieldDocs(docs, plan));

            return [
              plan.name,
              docs || plan.column.description === undefined
                ? spec
                : { description: plan.column.description, ...spec },
            ];
          }),
        ),
      });

      defs[`${key}${variant}`] = withDeprecated(
        schema,
        table.deprecated === true,
        plans.filter((plan) => plan.column.deprecated).map((plan) => plan.name),
      );
    }
  }

  for (const schema of extras.inputs) {
    defs[schema.name] = tableJsonSchema({
      title: schema.title,
      fields: schema.fields,
    });
  }

  const prefix = target === "draft-2020-12" ? "#/$defs/" : "#/definitions/";

  for (const result of extras.results) {
    const schema = resultJsonSchema(result, defs, prefix);

    if (schema) {
      defs[result.name] = schema;
    }
  }

  switch (target) {
    case "draft-2020-12": {
      return {
        $schema: "https://json-schema.org/draft/2020-12/schema",
        ...(id ? { $id: id } : {}),
        $defs: defs,
      };
    }

    case "draft-07": {
      return forTarget(
        {
          ...(id ? { $id: id } : {}),
          definitions: Object.fromEntries(
            Object.entries(defs).map(([name, def]) => [name, toDraft07(def)]),
          ),
        },
        "draft-07",
      );
    }

    case "openapi-3.0": {
      return {
        ...(id ? { $id: id } : {}),
        definitions: Object.fromEntries(
          Object.entries(defs).map(([name, def]) => [
            name,
            forTarget(def, "openapi-3.0"),
          ]),
        ),
      };
    }

    default: {
      const exhaustive: never = target;

      return exhaustive;
    }
  }
}

/** Writes the JSON Schema document; `createOpenApi` reuses the same `$defs`. */
export function jsonSchema(
  options: JsonSchemaGeneratorOptions = {},
): Generator {
  return {
    apiVersion: 1,
    name: "json-schema",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "schema.json");

      const extras = extraSchemas(input);

      const document = buildJsonSchema(
        input,
        options.id,
        options.target,
        extras,
      );

      return [
        {
          path,
          contents: `${JSON.stringify(options.fieldMeta ? labelled(document, fieldMeta(input, extras)) : document, null, 2)}\n`,
        },
      ];
    },
  };
}

/** The document with `fieldMeta` labels on each table's Insert and each input. */
function labelled(
  document: JsonSchema,
  meta: Readonly<Record<string, Readonly<Record<string, FieldMeta>>>>,
): JsonSchema {
  const key = "$defs" in document ? "$defs" : "definitions";
  const defs = document[key];

  if (typeof defs !== "object" || !defs) {
    return document;
  }

  return {
    ...document,
    [key]: Object.fromEntries(
      Object.entries(defs).map(([name, def]: [string, unknown]) => {
        const labels =
          meta[name] ??
          (name.endsWith("Insert") ? meta[name.slice(0, -6)] : undefined);

        return [name, isJsonObject(def) ? withLabels(def, labels) : def];
      }),
    ),
  };
}

function isJsonObject(value: unknown): value is JsonSchema {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
