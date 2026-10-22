import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";
import type { FieldOptions, FieldSpec } from "../core/table-json-schema.ts";
import type { ExtraSchemas, ResultSchema } from "./extras.ts";
import type { FieldDocs, FieldPlan, ScalarKind } from "./shared.ts";

import {
  extraKinds,
  extraSchemas,
  fieldMetaLines,
  objectType,
  resultType,
} from "./extras.ts";
import {
  fieldDocs,
  fieldsFor,
  HEADER,
  optionalLine,
  parseImport,
  propertyKey,
  rowType,
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
  /**
   * Schemas for typed jsonb columns: `{ 'customers.metadata':
   * './schemas.ts#metadata' }`.
   */
  readonly json?: Readonly<Record<string, string>>;
  /**
   * `classic` (the default) imports `zod` and chains methods; `mini` imports
   * `zod/mini` and uses its functional API (`z.nullable(...)`, `.check(...)`),
   * which tree-shakes to a smaller bundle. Both need zod 4.
   */
  readonly flavor?: ZodFlavor;
  /**
   * Also export `fieldMeta`: a label, a required flag, enum options and bounds
   * for each writable field, for building forms.
   */
  readonly fieldMeta?: boolean;
}

export type ZodFlavor = "classic" | "mini";

function scalar(kind: ScalarKind): string {
  switch (kind.kind) {
    case "uuid": {
      return "z.guid()";
    }

    case "string": {
      return "z.string()";
    }

    case "integer": {
      return "z.int()";
    }

    case "number": {
      return "z.number()";
    }

    case "boolean": {
      return "z.boolean()";
    }

    case "datetime": {
      return "z.iso.datetime({ offset: true })";
    }

    case "date": {
      return "z.iso.date()";
    }

    case "instant": {
      return "z.custom<Temporal.Instant>(isInstant)";
    }

    case "plainDate": {
      return "z.custom<Temporal.PlainDate>(isPlainDate)";
    }

    case "plainDateTime": {
      return "z.custom<Temporal.PlainDateTime>(isPlainDateTime)";
    }

    case "bigint": {
      return "z.bigint()";
    }

    case "json": {
      return "z.json()";
    }

    case "enum": {
      return `z.enum([${kind.values.map((value) => JSON.stringify(value)).join(", ")}])`;
    }

    case "unknown": {
      return "z.unknown()";
    }

    default: {
      const exhaustive: never = kind;

      return exhaustive;
    }
  }
}

function bounds(docs: FieldDocs, flavor: ZodFlavor): string {
  if (flavor === "mini") {
    const checks = [
      docs.minimum === undefined ? "" : `z.gte(${docs.minimum})`,
      docs.exclusiveMinimum === undefined
        ? ""
        : `z.gt(${docs.exclusiveMinimum})`,
      docs.maximum === undefined ? "" : `z.lte(${docs.maximum})`,
      docs.exclusiveMaximum === undefined
        ? ""
        : `z.lt(${docs.exclusiveMaximum})`,
      docs.minLength === undefined ? "" : `z.minLength(${docs.minLength})`,
      docs.maxLength === undefined ? "" : `z.maxLength(${docs.maxLength})`,
    ].filter((check) => check !== "");

    return checks.length === 0 ? "" : `.check(${checks.join(", ")})`;
  }

  return [
    docs.minimum === undefined ? "" : `.min(${docs.minimum})`,
    docs.exclusiveMinimum === undefined ? "" : `.gt(${docs.exclusiveMinimum})`,
    docs.maximum === undefined ? "" : `.max(${docs.maximum})`,
    docs.exclusiveMaximum === undefined ? "" : `.lt(${docs.exclusiveMaximum})`,
    docs.minLength === undefined ? "" : `.min(${docs.minLength})`,
    docs.maxLength === undefined ? "" : `.max(${docs.maxLength})`,
  ].join("");
}

/**
 * `.meta({ ... })` (`.check(z.meta({ ... }))` in mini) for the entries that are
 * set, or nothing.
 */
function meta(
  entries: Readonly<Record<string, unknown>>,
  flavor: ZodFlavor,
): string {
  const set = Object.entries(entries).filter(
    ([, value]) => value !== undefined,
  );

  if (set.length === 0) {
    return "";
  }

  const object = `{ ${set.map(([key, value]) => `${key}: ${JSON.stringify(value)}`).join(", ")} }`;

  return flavor === "mini" ? `.check(z.meta(${object}))` : `.meta(${object})`;
}

function field(
  table: string,
  plan: FieldPlan,
  jsonImports: ReadonlyMap<string, string>,
  docs: FieldDocs,
  flavor: ZodFlavor,
): string {
  const imported = jsonImports.get(`${table}.${plan.column.db}`);

  const expr =
    imported ??
    (plan.customJson
      ? `z.custom<NonNullable<RowOf<'${table}'>['${plan.name}']>>((value) => value !== undefined)`
      : plan.column.storage === undefined
        ? `${scalar(plan.scalar)}${bounds(docs, flavor)}`
        : `(z.string() as unknown as ${typeName(flavor)}<${rowType(table, plan)}>)`);

  return `  ${propertyKey(plan.name)}: ${wrap(
    expr,
    {
      array: plan.column.array === true,
      nullable: plan.nullable,
      optional: plan.optional,
      ...docs,
    },
    flavor,
  )},`;
}

/** `expr` as an array, nullable, documented and optional, as `spec` says. */
function wrap(expr: string, spec: FieldOptions, flavor: ZodFlavor): string {
  const mini = flavor === "mini";
  let out = spec.array ? `z.array(${expr})` : expr;

  if (spec.nullable) {
    out = mini ? `z.nullable(${out})` : `${out}.nullable()`;
  }

  out += meta(
    { description: spec.description, examples: spec.examples },
    flavor,
  );

  if (spec.optional) {
    out = mini ? `z.exactOptional(${out})` : `${out}.exactOptional()`;
  }

  return out;
}

function specExpr(spec: FieldSpec, flavor: ZodFlavor): string {
  return wrap(
    spec.kind === "custom"
      ? "z.unknown()"
      : `${scalar(spec)}${bounds(spec, flavor)}`,
    spec,
    flavor,
  );
}

function resultExpr(
  result: ResultSchema,
  rows: ReadonlySet<string>,
  flavor: ZodFlavor,
): string | undefined {
  const mini = flavor === "mini";

  if (result.of.kind === "row") {
    if (!rows.has(result.of.table)) {
      return undefined;
    }

    const row = schemaName(result.of.table, "Row");

    if (result.set) {
      return `z.array(${row})`;
    }

    return mini ? `z.nullable(${row})` : `${row}.nullable()`;
  }

  const item = scalar(result.of.scalar);
  const nullable = mini ? `z.nullable(${item})` : `${item}.nullable()`;

  if (result.set) {
    return `z.array(${result.nullable ? nullable : item})`;
  }

  return result.nullable ? nullable : item;
}

function extraLines(
  input: GeneratorInput,
  extras: ExtraSchemas,
  flavor: ZodFlavor,
): string[] {
  const lines: string[] = [];

  for (const schema of extras.inputs) {
    lines.push(
      "",
      `export const ${schema.name}: ${typeName(flavor)}<${objectType(schema)}> = z.object({`,
    );

    for (const [name, spec] of Object.entries(schema.fields)) {
      lines.push(`  ${propertyKey(name)}: ${specExpr(spec, flavor)},`);
    }

    lines.push(`})${meta({ title: schema.title }, flavor)};`);
  }

  const rows = new Set(Object.keys(input.meta.tables));

  for (const result of extras.results) {
    const expr = resultExpr(result, rows, flavor);

    if (expr !== undefined) {
      lines.push(
        "",
        `export const ${result.name}: ${typeName(flavor)}<${resultType(result)}> = ${expr};`,
      );
    }
  }

  return lines;
}

function typeName(flavor: ZodFlavor): string {
  return flavor === "mini" ? "z.ZodMiniType" : "z.ZodType";
}

/**
 * Zod 4 schemas for every table's Row, Insert and Update shape, for `zod` or,
 * with `flavor: 'mini'`, `zod/mini`.
 */
export function zod(options: ZodGeneratorOptions = {}): Generator {
  const flavor = options.flavor ?? "classic";

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

      const extras = extraSchemas(input);
      const kinds = extraKinds(extras);

      const lines = [
        HEADER,
        flavor === "mini"
          ? 'import { z } from "zod/mini";'
          : 'import { z } from "zod";',
        ...optionalLine(temporalGuardImport(input, kinds)),
        "",
        `import type { InsertOf, ${kinds.includes("json") ? "Json, " : ""}RowOf, UpdateOf } from ${JSON.stringify(input.importPath(path, input.config.output))};`,
      ];

      for (const [from, names] of imports) {
        lines.push(
          `import { ${[...new Set(names)].toSorted().join(", ")} } from ${JSON.stringify(from)};`,
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
            `export const ${name}: ${typeName(flavor)}<${variant}Of<'${key}'>> = z.object({`,
          );

          for (const plan of fieldsFor(table, variant, input)) {
            lines.push(
              field(key, plan, jsonImports, fieldDocs(docs, plan), flavor),
            );
          }

          lines.push(
            `})${docs ? meta({ title: variantTitle(docs, variant), description: docs.description }, flavor) : ""};`,
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
        "/** Write validators; the generated schema installs them through `validation`. */",
        "export const validators: {",
      );

      for (const [key, table] of tableEntries(input)) {
        if (!variantsFor(table).includes("Insert")) {
          continue;
        }

        lines.push(
          `  readonly ${propertyKey(key)}: { readonly insert: typeof ${schemaName(key, "Insert")}; readonly update: typeof ${schemaName(key, "Update")} };`,
        );
      }

      lines.push(
        "} = {",
        ...validators,
        "};",
        ...extraLines(input, extras, flavor),
        ...(options.fieldMeta ? fieldMetaLines(input, extras) : []),
        "",
      );

      return [{ path, contents: lines.join("\n"), validators: true }];
    },
  };
}
