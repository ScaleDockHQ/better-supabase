import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import { extraSchemas, fieldMetaLines, objectType } from "./extras.ts";
import {
  fieldDocs,
  fieldSpec,
  fieldsFor,
  HEADER,
  parseImport,
  propertyKey,
  schemaName,
  siblingPath,
  tableDocs,
  tableEntries,
  variantsFor,
  variantTitle,
} from "./shared.ts";

export interface StandardSchemaGeneratorOptions {
  /**
   * Output path relative to the project root. Defaults to
   * `<output>.standard.ts`.
   */
  readonly output?: string;
  /**
   * Standard Schemas for typed jsonb columns: `{ 'customers.metadata':
   * './schemas.ts#metadata' }`.
   */
  readonly json?: Readonly<Record<string, string>>;
  /**
   * Also export `fieldMeta`: a label, a required flag, enum options and bounds
   * for each writable field, for building forms.
   */
  readonly fieldMeta?: boolean;
}

/**
 * Standard Schemas for every table's Row, Insert and Update shape, with no
 * validation library. Each one also converts to JSON Schema (Standard JSON
 * Schema), and `validators` plugs into the validation plugin.
 */
export function standardSchema(
  options: StandardSchemaGeneratorOptions = {},
): Generator {
  return {
    apiVersion: 1,
    name: "standard-schema",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "standard.ts");

      const imports = new Map<string, string[]>();
      const jsonImports = new Map<string, string>();

      const tableNames = new Map(
        Object.values(input.meta.tables).map((t) => [t.name, t.key]),
      );

      for (const [key, spec] of Object.entries(options.json ?? {})) {
        const [tableName, column] = key.split(".");
        const { from, name } = parseImport(spec);

        const specifier = from.startsWith(".")
          ? input.importPath(path, from)
          : from;

        imports.set(specifier, [...(imports.get(specifier) ?? []), name]);
        jsonImports.set(
          `${tableNames.get(tableName ?? "") ?? tableName}.${column}`,
          name,
        );
      }

      const extras = extraSchemas(input);

      const usesJson = extras.inputs.some((schema) =>
        Object.values(schema.fields).some((field) => field.kind === "json"),
      );

      const lines = [
        HEADER,
        `import { type TableSchema, tableSchema } from ${JSON.stringify(input.runtimeImport ?? "better-supabase")};`,
        "",
        `import type { InsertOf, ${usesJson ? "Json, " : ""}RowOf, UpdateOf } from ${JSON.stringify(input.importPath(path, input.config.output))};`,
      ];

      for (const [from, names] of imports) {
        lines.push(
          `import { ${[...new Set(names)].toSorted().join(", ")} } from ${JSON.stringify(from)};`,
        );
      }

      const validators: string[] = [];
      const validatorTypes: string[] = [];

      for (const [key, table] of tableEntries(input)) {
        const variants = variantsFor(table);
        const docs = tableDocs(input, table);

        for (const variant of variants) {
          lines.push(
            "",
            `export const ${schemaName(key, variant)}: TableSchema<${variant}Of<'${key}'>> = tableSchema({`,
          );

          if (docs) {
            lines.push(
              `  title: ${JSON.stringify(variantTitle(docs, variant))},`,
            );

            if (docs.description !== undefined) {
              lines.push(`  description: ${JSON.stringify(docs.description)},`);
            }
          }

          lines.push("  fields: {");

          for (const plan of fieldsFor(table, variant, input)) {
            const imported = jsonImports.get(`${key}.${plan.column.db}`);

            const entries = Object.entries(
              fieldSpec(plan, fieldDocs(docs, plan)),
            ).map(([name, value]) => `${name}: ${JSON.stringify(value)}`);

            if (imported) {
              entries.push(`schema: ${imported}`);
            }

            lines.push(
              `    ${propertyKey(plan.name)}: { ${entries.join(", ")} },`,
            );
          }

          lines.push("  },", "});");
        }

        if (variants.includes("Insert")) {
          const insert = schemaName(key, "Insert");
          const update = schemaName(key, "Update");
          validators.push(
            `  ${propertyKey(key)}: { insert: ${insert}, update: ${update} },`,
          );
          validatorTypes.push(
            `  readonly ${propertyKey(key)}: { readonly insert: typeof ${insert}; readonly update: typeof ${update} };`,
          );
        }
      }

      lines.push(
        "",
        "/** Write validators for the validation plugin. */",
        "export const validators: {",
        ...validatorTypes,
        "} = {",
        ...validators,
        "};",
      );

      for (const schema of extras.inputs) {
        lines.push(
          "",
          `export const ${schema.name}: TableSchema<${objectType(schema)}> = tableSchema({`,
          `  title: ${JSON.stringify(schema.title)},`,
          "  fields: {",
          ...Object.entries(schema.fields).map(
            ([name, spec]) =>
              `    ${propertyKey(name)}: ${JSON.stringify(spec)},`,
          ),
          "  },",
          "});",
        );
      }

      lines.push(
        ...(options.fieldMeta ? fieldMetaLines(input, extras) : []),
        "",
      );

      return [{ path, contents: lines.join("\n") }];
    },
  };
}
