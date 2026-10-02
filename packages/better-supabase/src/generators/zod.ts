import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import {
  type FieldPlan,
  fieldsFor,
  HEADER,
  parseImport,
  propertyKey,
  rowType,
  type ScalarKind,
  schemaName,
  siblingPath,
  tableEntries,
  variantsFor,
} from "./shared.ts";

export interface ZodGeneratorOptions {
  /** Output path relative to the project root. Defaults to `<output>.zod.ts`. */
  readonly output?: string;
  /** Schemas for typed jsonb columns: `{ 'customers.metadata': './schemas.ts#metadata' }`. */
  readonly json?: Readonly<Record<string, string>>;
}

function scalar(kind: ScalarKind): string {
  switch (kind.kind) {
    case "uuid":
      return "z.guid()";
    case "string":
      return "z.string()";
    case "integer":
      return "z.int()";
    case "number":
      return "z.number()";
    case "boolean":
      return "z.boolean()";
    case "datetime":
      return "z.iso.datetime({ offset: true })";
    case "date":
      return "z.iso.date()";
    case "dateObject":
      return "z.date()";
    case "bigint":
      return "z.bigint()";
    case "json":
      return "z.json()";
    case "enum":
      return `z.enum([${kind.values.map((value) => JSON.stringify(value)).join(", ")}])`;
    case "unknown":
      return "z.unknown()";
    default: {
      const exhaustive: never = kind;
      return exhaustive;
    }
  }
}

function field(
  table: string,
  plan: FieldPlan,
  jsonImports: ReadonlyMap<string, string>,
): string {
  const imported = jsonImports.get(`${table}.${plan.column.db}`);
  let expr =
    imported ??
    (plan.customJson
      ? `z.custom<NonNullable<RowOf<'${table}'>['${plan.name}']>>((value) => value !== undefined)`
      : plan.column.storage === undefined
        ? scalar(plan.scalar)
        : `(z.string() as unknown as z.ZodType<${rowType(table, plan)}>)`);
  if (plan.column.array) expr = `z.array(${expr})`;
  if (plan.nullable) expr = `${expr}.nullable()`;
  if (plan.optional) expr = `${expr}.exactOptional()`;
  return `  ${propertyKey(plan.name)}: ${expr},`;
}

/** Zod 4 schemas for every table's Row, Insert and Update shape. */
export function zod(options: ZodGeneratorOptions = {}): Generator {
  return {
    name: "zod",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path = options.output ?? siblingPath(input.config.output, "zod.ts");
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

      const lines = [
        HEADER,
        'import { z } from "zod";',
        "",
        `import type { InsertOf, RowOf, UpdateOf } from ${JSON.stringify(input.importPath(path, input.config.output))};`,
      ];
      for (const [from, names] of imports) {
        lines.push(
          `import { ${[...new Set(names)].sort().join(", ")} } from ${JSON.stringify(from)};`,
        );
      }

      const validators: string[] = [];
      for (const [key, table] of tableEntries(input)) {
        lines.push("");
        const variants = variantsFor(table);
        for (const variant of variants) {
          const name = schemaName(key, variant);
          lines.push(
            `export const ${name}: z.ZodType<${variant}Of<'${key}'>> = z.object({`,
          );
          for (const plan of fieldsFor(table, variant, input)) {
            lines.push(field(key, plan, jsonImports));
          }
          lines.push("});");
        }
        if (variants.includes("Insert")) {
          validators.push(
            `  ${propertyKey(key)}: { insert: ${schemaName(key, "Insert")}, update: ${schemaName(key, "Update")} },`,
          );
        }
      }

      lines.push(
        "",
        "/** Write validators for the validation plugin. */",
        "export const validators: {",
      );
      for (const [key, table] of tableEntries(input)) {
        if (!variantsFor(table).includes("Insert")) continue;
        lines.push(
          `  readonly ${propertyKey(key)}: { readonly insert: typeof ${schemaName(key, "Insert")}; readonly update: typeof ${schemaName(key, "Update")} };`,
        );
      }
      lines.push("} = {", ...validators, "};", "");
      return [{ path, contents: lines.join("\n") }];
    },
  };
}
