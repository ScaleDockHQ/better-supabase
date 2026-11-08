import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import { VERSION } from "../core/version.ts";
import {
  extraSchemas,
  fieldDocs,
  fieldMetaLines,
  fieldsFor,
  fieldSpec,
  HEADER,
  objectType,
  parseImport,
  propertyKey,
  relativeImport,
  schemaName,
  siblingPath,
  tableDocs,
  tableEntries,
  variantsFor,
  variantTitle,
} from "./kit.ts";

export interface StandardSchemaGeneratorOptions {
  /**
   * Output path relative to the project root. Defaults to
   * `<output>.standard.ts`.
   */
  readonly output?: string;
  /**
   * Install these schemas as the schema's `validation`, so writes are checked.
   * Only one configured generator may; set `false` on the others. Defaults to
   * `true`.
   */
  readonly validators?: boolean;
  /**
   * Standard Schemas for typed jsonb columns: `{ 'customers.metadata':
   * './schemas.ts#metadata' }`.
   */
  readonly json?: Readonly<Record<string, string>>;
  /**
   * The project's `defineSettings()` result, `'./settings.ts#settings'`. The
   * `settings` block checks its keys with these schemas when
   * `blocks.settings.options.schemas` is unset.
   */
  readonly settings?: string;
  /**
   * Also export `fieldMeta`: a label, a required flag, enum options and bounds
   * for each writable field, for building forms.
   */
  readonly fieldMeta?: boolean;
}

/**
 * Standard Schemas for every table's Row, Insert and Update shape, with no
 * validation library. Each one also converts to JSON Schema (Standard JSON
 * Schema), and `validators` is what the generated schema checks writes with.
 */
export function standardSchema(
  options: StandardSchemaGeneratorOptions = {},
): Generator {
  return {
    apiVersion: 2,
    version: VERSION,
    options,
    pure: true,
    provides: options.validators === false ? [] : ["validators"],
    workerSafe: true,
    module: {
      specifier: "better-supabase/generators/standard-schema",
      export: "standardSchema",
    },
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
          ? relativeImport(path, from)
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
        `import { type TableSchema, tableSchema } from ${JSON.stringify(input.imports.runtime)};`,
        "",
        `import type { InsertOf, ${usesJson ? "Json, " : ""}RowOf, UpdateOf } from ${JSON.stringify(relativeImport(path, input.config.output))};`,
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
        "/** Write validators; the generated schema installs them through `validation`. */",
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
