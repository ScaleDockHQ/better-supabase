import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import { tableJsonSchema } from "../core/table-json-schema.ts";
import { forTarget } from "../core/table-schema.ts";
import { type JsonSchemaTarget, toDraft07 } from "./json-schema-target.ts";
import {
  type DocsSource,
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
  /** Output path relative to the project root. Defaults to `<output>.schema.json`. */
  readonly output?: string;
  /** `$id` of the document. */
  readonly id?: string;
  /**
   * The dialect. `draft-2020-12` (the default) writes `$defs`; `draft-07`
   * and `openapi-3.0` (`nullable`, `example`) write `definitions`.
   */
  readonly target?: JsonSchemaTarget;
}

type JsonSchema = Record<string, unknown>;

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

/**
 * JSON Schema `$defs` for every table: `customersRow`, `customersInsert`,
 * ... `target` lowers the document to draft-07 or the OpenAPI 3.0 dialect,
 * which keep the schemas under `definitions`.
 */
export function buildJsonSchema(
  input: DocsSource,
  id?: string,
  target: JsonSchemaTarget = "draft-2020-12",
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
      return [
        {
          path,
          contents: `${JSON.stringify(buildJsonSchema(input, options.id, options.target), null, 2)}\n`,
        },
      ];
    },
  };
}
