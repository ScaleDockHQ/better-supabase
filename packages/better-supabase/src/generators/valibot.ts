import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import {
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
  tableEntries,
  temporalGuardImport,
  variantsFor,
} from "./shared.ts";

export interface ValibotGeneratorOptions {
  /** Output path relative to the project root. Defaults to `<output>.valibot.ts`. */
  readonly output?: string;
  /** Schemas for typed jsonb columns: `{ 'customers.metadata': './schemas.ts#metadata' }`. */
  readonly json?: Readonly<Record<string, string>>;
}

function scalar(kind: ScalarKind): string {
  switch (kind.kind) {
    case "uuid":
      return "v.pipe(v.string(), v.uuid())";
    case "string":
      return "v.string()";
    case "integer":
      return "v.pipe(v.number(), v.integer())";
    case "number":
      return "v.number()";
    case "boolean":
      return "v.boolean()";
    case "datetime":
      return "v.pipe(v.string(), v.isoTimestamp())";
    case "date":
      return "v.pipe(v.string(), v.isoDate())";
    case "instant":
      return "v.custom<Temporal.Instant>(isInstant)";
    case "plainDateTime":
      return "v.custom<Temporal.PlainDateTime>(isPlainDateTime)";
    case "bigint":
      return "v.bigint()";
    case "json":
      return "json";
    case "enum":
      return `v.picklist([${kind.values.map((value) => JSON.stringify(value)).join(", ")}])`;
    case "unknown":
      return "v.unknown()";
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
      ? `v.custom<NonNullable<RowOf<'${table}'>['${plan.name}']>>((value) => value !== undefined)`
      : plan.column.storage === undefined
        ? scalar(plan.scalar)
        : `(v.string() as unknown as v.GenericSchema<${rowType(table, plan)}>)`);
  if (plan.column.array) expr = `v.array(${expr})`;
  if (plan.nullable) expr = `v.nullable(${expr})`;
  if (plan.optional) expr = `v.exactOptional(${expr})`;
  return `  ${propertyKey(plan.name)}: ${expr},`;
}

/** Valibot schemas for every table's Row, Insert and Update shape. */
export function valibot(options: ValibotGeneratorOptions = {}): Generator {
  return {
    name: "valibot",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "valibot.ts");
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
        'import * as v from "valibot";',
        ...optionalLine(temporalGuardImport(input)),
        "",
        `import type { InsertOf, Json, RowOf, UpdateOf } from ${JSON.stringify(input.importPath(path, input.config.output))};`,
      ];
      for (const [from, names] of imports) {
        lines.push(
          `import { ${[...new Set(names)].sort().join(", ")} } from ${JSON.stringify(from)};`,
        );
      }
      lines.push(
        "",
        "const json: v.GenericSchema<Json> = v.lazy(() =>",
        "  v.union([v.string(), v.number(), v.boolean(), v.null(), v.array(json), v.record(v.string(), v.optional(json))]),",
        ");",
      );

      const validators: string[] = [];
      const validatorTypes: string[] = [];
      for (const [key, table] of tableEntries(input)) {
        lines.push("");
        const variants = variantsFor(table);
        for (const variant of variants) {
          const name = schemaName(key, variant);
          lines.push(
            `export const ${name}: v.GenericSchema<${variant}Of<'${key}'>> = v.object({`,
          );
          for (const plan of fieldsFor(table, variant, input))
            lines.push(field(key, plan, jsonImports));
          lines.push("});");
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
        "",
      );
      return [{ path, contents: lines.join("\n") }];
    },
  };
}
