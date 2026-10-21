import type {
  GeneratedFile,
  Generator,
  GeneratorColumn,
  GeneratorInput,
  GeneratorTable,
} from "../config/index.ts";

import { HEADER, siblingPath } from "./shared.ts";

export interface FactoriesGeneratorOptions {
  /**
   * Output path relative to the project root. Defaults to
   * `<output>.factories.ts`.
   */
  readonly output?: string;
  /**
   * The table keys to write factories for. Defaults to every table, block
   * tables included under their final names.
   */
  readonly tables?: readonly string[];
  /**
   * Where the file imports the factory runtime from. Defaults to
   * `better-supabase/testing` (under `runtimeImport`).
   */
  readonly testingImport?: string;
}

interface Bounds {
  min?: number;
  max?: number;
  minLength?: number;
  maxLength?: number;
}

interface FactoryColumn {
  readonly column: GeneratorColumn;
  /** The column the parent row is read from, for a foreign key. */
  readonly ref: string | undefined;
  /** The default expression for call `n`; undefined when a call needs it. */
  readonly value: string | undefined;
}

const NUMBER = String.raw`(-?\d+(?:\.\d+)?)`;

/** The call number as the generated template literal interpolates it. */
const N = ["$", "{String(n)}"].join("");

function escape(name: string): string {
  return name.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);
}

function tighten(bounds: Bounds, op: string, value: number): void {
  switch (op) {
    case ">=":
    case ">": {
      const min = op === ">" ? value + 1 : value;
      bounds.min = Math.max(bounds.min ?? min, min);
      break;
    }

    case "<=":
    case "<": {
      const max = op === "<" ? value - 1 : value;
      bounds.max = Math.min(bounds.max ?? max, max);
      break;
    }

    default: {
      break;
    }
  }
}

const FLIP: Readonly<Record<string, string>> = {
  ">=": "<=",
  ">": "<",
  "<=": ">=",
  "<": ">",
};

/** Numeric and length bounds a check constraint puts on `db`. */
export function checkBounds(db: string, checks: readonly string[]): Bounds {
  const name = String.raw`"?${escape(db)}"?`;
  const bounds: Bounds = {};
  const lengths: Bounds = {};

  for (const check of checks) {
    const length = new RegExp(
      String.raw`(?:char_length|length)\(\s*${name}(?:::\w+)?\s*\)\s*(>=|>|<=|<)\s*${NUMBER}`,
      "gi",
    );

    for (const [, op = "", value = ""] of check.matchAll(length)) {
      tighten(lengths, op, Number(value));
    }

    const after = new RegExp(
      String.raw`(?<![\w.])${name}(?:::\w+)?\s*(>=|>|<=|<)\s*\(?\s*${NUMBER}`,
      "gi",
    );

    for (const [, op = "", value = ""] of check.matchAll(after)) {
      tighten(bounds, op, Number(value));
    }

    const before = new RegExp(
      String.raw`${NUMBER}\s*\)?\s*(>=|>|<=|<)\s*${name}(?![\w(])`,
      "gi",
    );

    for (const [, value = "", op = ""] of check.matchAll(before)) {
      tighten(bounds, FLIP[op] ?? op, Number(value));
    }

    const between = new RegExp(
      String.raw`${name}\s+between\s+${NUMBER}\s+and\s+${NUMBER}`,
      "gi",
    );

    for (const [, low = "", high = ""] of check.matchAll(between)) {
      tighten(bounds, ">=", Number(low));
      tighten(bounds, "<=", Number(high));
    }
  }

  return {
    ...bounds,
    ...(lengths.min === undefined ? {} : { minLength: lengths.min }),
    ...(lengths.max === undefined ? {} : { maxLength: lengths.max }),
  };
}

function numberValue(bounds: Bounds): string {
  const { min, max } = bounds;

  if (min !== undefined && max !== undefined) {
    return max <= min
      ? String(min)
      : `${String(min)} + ((n - 1) % ${String(max - min + 1)})`;
  }

  if (min !== undefined) {
    return min === 1 ? "n" : `${String(min)} + n - 1`;
  }

  return max === undefined ? "n" : `Math.min(${String(max)}, n)`;
}

function textValue(column: GeneratorColumn, bounds: Bounds): string {
  let value = `\`${column.db.replaceAll("_", "-")}-${N}\``;

  if (bounds.minLength !== undefined && bounds.minLength > column.db.length) {
    value = `${value}.padEnd(${String(bounds.minLength)}, "x")`;
  }

  if (bounds.maxLength !== undefined) {
    value = `${value}.slice(0, ${String(bounds.maxLength)})`;
  }

  return value;
}

const TEMPORAL: Readonly<Record<string, string>> = {
  "Temporal.Instant": 'Temporal.Instant.from("2026-01-01T00:00:00Z")',
  "Temporal.PlainDate": 'Temporal.PlainDate.from("2026-01-01")',
  "Temporal.PlainDateTime":
    'Temporal.PlainDateTime.from("2026-01-01T00:00:00")',
  "Temporal.PlainTime": 'Temporal.PlainTime.from("00:00:00")',
};

const STRING_FORMATS: Readonly<Record<string, string>> = {
  uuid: `\`00000000-0000-4000-8000-${["$", '{String(n).padStart(12, "0")}'].join("")}\``,
  date: '"2026-01-01"',
  timestamptz: '"2026-01-01T00:00:00Z"',
  timestamp: '"2026-01-01T00:00:00"',
  time: '"00:00:00"',
};

/** The default for one required column, or undefined when a call needs it. */
function defaultValue(
  column: GeneratorColumn,
  format: string | undefined,
  bounds: Bounds,
): string | undefined {
  if (column.values !== undefined) {
    return JSON.stringify(column.values[0]);
  }

  const bucket = /^StoragePath<"([^"]+)">$/.exec(column.tsType)?.[1];

  if (bucket !== undefined) {
    return `factoryPath(${JSON.stringify(bucket)}, \`${column.app}/${N}\`)`;
  }

  if (column.tsType.endsWith("[]")) {
    return "[]";
  }

  if (column.json) {
    return column.tsType === "Json" ? "{}" : undefined;
  }

  const temporal = TEMPORAL[column.tsType];

  if (temporal !== undefined) {
    return temporal;
  }

  switch (column.tsType) {
    case "boolean": {
      return "false";
    }

    case "bigint": {
      return "BigInt(n)";
    }

    case "number": {
      return numberValue(bounds);
    }

    case "string": {
      const formatted =
        format === undefined ? undefined : STRING_FORMATS[format];

      if (formatted !== undefined) {
        return formatted;
      }

      return /email/i.test(column.app)
        ? `\`user${N}@example.com\``
        : textValue(column, bounds);
    }

    default: {
      return undefined;
    }
  }
}

function sortByKey(a: GeneratorTable, b: GeneratorTable): number {
  return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
}

function camel(noun: string): string {
  return noun.replaceAll(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function planTable(
  table: GeneratorTable,
  input: GeneratorInput,
): FactoryColumn[] {
  const { introspection, extras, model } = input;

  const checks = (
    extras.tables.find(
      (entry) => entry.schema === table.schema && entry.name === table.name,
    )?.checks ?? []
  ).map((check) => check.definition);

  const columns = introspection.columns.filter(
    (entry) => entry.schema === table.schema && entry.table === table.name,
  );

  const refs = new Map<string, string>();

  const relationships = introspection.relationships
    .filter(
      (relationship) =>
        relationship.schema === table.schema &&
        relationship.relation === table.name,
    )
    .toSorted((a, b) => a.columns.length - b.columns.length);

  for (const relationship of relationships) {
    const parent = model.tables.find(
      (entry) =>
        entry.schema === relationship.referenced_schema &&
        entry.name === relationship.referenced_relation,
    );

    for (const [index, db] of relationship.columns.entries()) {
      const target = relationship.referenced_columns[index];

      if (target === undefined || refs.has(db)) {
        continue;
      }

      refs.set(
        db,
        parent?.columns.find((column) => column.db === target)?.app ?? target,
      );
    }
  }

  return table.columns
    .filter((column) => !column.readonly)
    .map((column) => {
      const ref = refs.get(column.db);
      const meta = columns.find((entry) => entry.name === column.db);
      const own = meta?.check ? [meta.check] : [];

      const value =
        column.optional || ref !== undefined
          ? undefined
          : defaultValue(
              column,
              meta?.format,
              checkBounds(column.db, [...own, ...checks]),
            );

      return { column, ref, value };
    });
}

function union(keys: readonly string[]): string {
  return keys.length === 0
    ? "never"
    : keys.map((key) => JSON.stringify(key)).join(" | ");
}

function tableLines(table: GeneratorTable, plan: readonly FactoryColumn[]) {
  const refs = plan.filter((entry) => entry.ref !== undefined);

  const required = plan.filter(
    (entry) => !entry.column.optional && entry.value === undefined,
  );

  const type = `Factory<InsertOf<${JSON.stringify(table.key)}>, ${union(refs.map((entry) => entry.column.app))}, ${union(required.map((entry) => entry.column.app))}>`;

  const defaults = plan.flatMap((entry) =>
    entry.value === undefined
      ? []
      : [`${JSON.stringify(entry.column.app)}: ${entry.value}`],
  );

  const refMap = refs.map(
    (entry) =>
      `${JSON.stringify(entry.column.app)}: ${JSON.stringify(entry.ref)}`,
  );

  const uses = defaults.some((line) => /\bn\b/.test(line));

  const object = (items: readonly string[]): string =>
    items.length === 0 ? "{}" : `{ ${items.join(", ")} }`;

  return {
    type,
    value: `defineFactory<InsertOf<${JSON.stringify(table.key)}>, ${union(refs.map((entry) => entry.column.app))}, ${union(required.map((entry) => entry.column.app))}>((${uses ? "n" : "_n"}) => (${object(defaults)}), ${object(refMap)})`,
  };
}

/**
 * Test factories, one per table: `factories.customers({ name })` returns an
 * insert row with valid defaults for the required columns. Defaults respect
 * enums, check-constraint bounds and `StoragePath` buckets. A foreign key takes
 * the parent row or its id, and a column without a safe default is a required
 * input. Block entities also get a factory under their singular noun
 * (`factories.task`). The file imports `better-supabase/testing`.
 */
export function factories(options: FactoriesGeneratorOptions = {}): Generator {
  return {
    apiVersion: 1,
    name: "factories",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "factories.ts");

      const wanted =
        options.tables === undefined ? undefined : new Set(options.tables);

      const tables = input.model.tables
        .filter(
          (table) =>
            (wanted === undefined || wanted.has(table.key)) &&
            input.introspection.tables.some(
              (entry) =>
                entry.schema === table.schema && entry.name === table.name,
            ),
        )
        .toSorted(sortByKey);

      const missing = [...(wanted ?? [])].filter(
        (key) => !tables.some((table) => table.key === key),
      );

      if (missing.length > 0) {
        throw new Error(
          `factories(): no table named ${missing.map((key) => `"${key}"`).join(", ")}`,
        );
      }

      const entries = tables.map((table) => ({
        key: table.key,
        plan: planTable(table, input),
        table,
      }));

      const lines = entries.map(({ key, plan, table }) => ({
        key,
        ...tableLines(table, plan),
      }));

      const aliases = input.model.blocks.flatMap((block) =>
        block.entities.flatMap((entity) => {
          const key = camel(entity.to.singular);

          const table = tables.find(
            (entry) =>
              entry.schema === block.schema && entry.name === entity.table,
          );

          return table === undefined ||
            table.key === key ||
            tables.some((entry) => entry.key === key)
            ? []
            : [{ key, target: table.key }];
        }),
      );

      const runtime =
        options.testingImport ??
        `${input.runtimeImport ?? "better-supabase"}/testing`;

      const usesPath = lines.some((line) =>
        line.value.includes("factoryPath("),
      );

      const local = (key: string): string => `${key}Factory`;

      const members = [
        ...lines.map((line) => ({ key: line.key, target: line.key })),
        ...aliases,
      ].toSorted((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));

      const contents = [
        HEADER,
        `import type { Factory } from ${JSON.stringify(runtime)};`,
        `import { defineFactory${usesPath ? ", factoryPath" : ""} } from ${JSON.stringify(runtime)};`,
        "",
        `import type { InsertOf } from ${JSON.stringify(input.importPath(path, input.config.output))};`,
        ...lines.flatMap((line) => [
          "",
          `const ${local(line.key)}: ${line.type} = ${line.value};`,
        ]),
        "",
        "/**",
        " * Insert rows with valid defaults, one factory per table and one per block",
        " * entity under the name the config gives it.",
        " */",
        "export const factories: {",
        ...members.map(
          ({ key, target }) => `  readonly ${key}: typeof ${local(target)};`,
        ),
        "} = {",
        ...members.map(({ key, target }) => `  ${key}: ${local(target)},`),
        "};",
        "",
      ].join("\n");

      return [{ path, contents }];
    },
  };
}
