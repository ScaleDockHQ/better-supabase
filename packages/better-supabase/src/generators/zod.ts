import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import {
  type FieldDocs,
  fieldDocs,
  type FieldPlan,
  fieldsFor,
  HEADER,
  optionalLine,
  parseImport,
  propertyKey,
  rowType,
  type ScalarKind,
  schemaName,
  siblingPath,
  tableDocs,
  tableEntries,
  temporalGuardImport,
  variantsFor,
  variantTitle,
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
    case "instant":
      return "z.custom<Temporal.Instant>(isInstant)";
    case "plainDateTime":
      return "z.custom<Temporal.PlainDateTime>(isPlainDateTime)";
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

function bounds(docs: FieldDocs): string {
  return [
    docs.minimum === undefined ? "" : `.min(${docs.minimum})`,
    docs.exclusiveMinimum === undefined ? "" : `.gt(${docs.exclusiveMinimum})`,
    docs.maximum === undefined ? "" : `.max(${docs.maximum})`,
    docs.exclusiveMaximum === undefined ? "" : `.lt(${docs.exclusiveMaximum})`,
    docs.minLength === undefined ? "" : `.min(${docs.minLength})`,
    docs.maxLength === undefined ? "" : `.max(${docs.maxLength})`,
  ].join("");
}

/** `.meta({ ... })` for the entries that are set, or nothing. */
function meta(entries: Readonly<Record<string, unknown>>): string {
  const set = Object.entries(entries).filter(
    ([, value]) => value !== undefined,
  );
  return set.length === 0
    ? ""
    : `.meta({ ${set.map(([key, value]) => `${key}: ${JSON.stringify(value)}`).join(", ")} })`;
}

function field(
  table: string,
  plan: FieldPlan,
  jsonImports: ReadonlyMap<string, string>,
  docs: FieldDocs,
): string {
  const imported = jsonImports.get(`${table}.${plan.column.db}`);
  let expr =
    imported ??
    (plan.customJson
      ? `z.custom<NonNullable<RowOf<'${table}'>['${plan.name}']>>((value) => value !== undefined)`
      : plan.column.storage === undefined
        ? `${scalar(plan.scalar)}${bounds(docs)}`
        : `(z.string() as unknown as z.ZodType<${rowType(table, plan)}>)`);
  if (plan.column.array) expr = `z.array(${expr})`;
  if (plan.nullable) expr = `${expr}.nullable()`;
  expr += meta({ description: docs.description, examples: docs.examples });
  if (plan.optional) expr = `${expr}.exactOptional()`;
  return `  ${propertyKey(plan.name)}: ${expr},`;
}

/** Zod 4 schemas for every table's Row, Insert and Update shape. */
export function zod(options: ZodGeneratorOptions = {}): Generator {
  return {
    apiVersion: 1,
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
        ...optionalLine(temporalGuardImport(input)),
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
        const docs = tableDocs(input, table);
        for (const variant of variants) {
          const name = schemaName(key, variant);
          lines.push(
            `export const ${name}: z.ZodType<${variant}Of<'${key}'>> = z.object({`,
          );
          for (const plan of fieldsFor(table, variant, input)) {
            lines.push(field(key, plan, jsonImports, fieldDocs(docs, plan)));
          }
          lines.push(
            `})${docs ? meta({ title: variantTitle(docs, variant), description: docs.description }) : ""};`,
          );
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
