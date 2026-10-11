import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import { tableJsonSchema } from "../core/table-json-schema.ts";
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

export interface JsonSchemaGeneratorOptions {
  /** Output path relative to the project root. Defaults to `<output>.schema.json`. */
  readonly output?: string;
  /** `$id` of the document. */
  readonly id?: string;
}

type JsonSchema = Record<string, unknown>;

/** JSON Schema (2020-12) `$defs` for every table: `customersRow`, `customersInsert`, ... */
export function buildJsonSchema(input: DocsSource, id?: string): JsonSchema {
  const defs: Record<string, JsonSchema> = {};
  for (const [key, table] of tableEntries(input)) {
    const docs = tableDocs(input, table);
    for (const variant of variantsFor(table)) {
      defs[`${key}${variant}`] = tableJsonSchema({
        ...(docs
          ? {
              title: variantTitle(docs, variant),
              ...(docs.description === undefined
                ? {}
                : { description: docs.description }),
            }
          : {}),
        fields: Object.fromEntries(
          fieldsFor(table, variant, input).map((plan) => [
            plan.name,
            fieldSpec(plan, fieldDocs(docs, plan)),
          ]),
        ),
      });
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
    apiVersion: 1,
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
