import type {
  GeneratedFile,
  Generator,
  GeneratorColumn,
  GeneratorInput,
  GeneratorTable,
} from "../config/index.ts";

import { HEADER, siblingPath } from "./shared.ts";

export interface NuqsGeneratorOptions {
  /** Output path relative to the project root. Defaults to `<output>.nuqs.ts`. */
  readonly output?: string;
  /**
   * The table keys to write search params for (`tasks`, `customerTags`).
   * Defaults to every table, block tables included under their final names.
   */
  readonly tables?: readonly string[];
  /** The page size `limit` defaults to. Defaults to 25. */
  readonly limit?: number;
}

/**
 * The list params every table gets; a column with one of these names is left
 * out.
 */
const LIST_PARAMS = new Set(["cursor", "direction", "limit", "orderBy"]);

const SORTABLE = new Set(["bigint", "boolean", "number", "string"]);

function sortable(column: GeneratorColumn): boolean {
  return (
    !column.json &&
    (column.values !== undefined ||
      SORTABLE.has(column.tsType) ||
      column.tsType.startsWith("Temporal."))
  );
}

function pascal(key: string): string {
  return key.replace(/^[a-z]/, (c) => c.toUpperCase());
}

function literal(values: readonly string[]): string {
  return `[${values.map((value) => JSON.stringify(value)).join(", ")}] as const`;
}

function union(values: readonly string[]): string {
  return values.map((value) => JSON.stringify(value)).join(" | ");
}

function tableLines(table: GeneratorTable, limit: number): string[] {
  const name = `${table.key.replace(/^[A-Z]/, (c) => c.toLowerCase())}SearchParams`;
  const params: [key: string, type: string, value: string][] = [];

  for (const column of table.columns) {
    if (column.values === undefined || LIST_PARAMS.has(column.app)) {
      continue;
    }

    params.push([
      column.app,
      `SingleParserBuilder<${union(column.values)}>`,
      `parseAsStringLiteral(${literal(column.values)})`,
    ]);
  }

  const orderBy = table.columns.filter(sortable).map((column) => column.app);

  if (orderBy.length > 0) {
    params.push([
      "orderBy",
      `SingleParserBuilder<${union(orderBy)}>`,
      `parseAsStringLiteral(${literal(orderBy)})`,
    ]);
  }

  params.push(
    [
      "direction",
      'SingleParserBuilder<"asc" | "desc"> & { readonly defaultValue: "asc" | "desc" }',
      `parseAsStringLiteral(${literal(["asc", "desc"])}).withDefault("asc")`,
    ],
    ["cursor", "SingleParserBuilder<string>", "parseAsString"],
    [
      "limit",
      "SingleParserBuilder<number> & { readonly defaultValue: number }",
      `parseAsInteger.withDefault(${String(limit)})`,
    ],
  );

  const map = `typeof ${name}`;

  return [
    "",
    `/** Search params for a list of \`${table.key}\`: filters, order, cursor and page size. */`,
    `export const ${name}: {`,
    ...params.map(([key, type]) => `  readonly ${key}: ${type};`),
    "} = {",
    ...params.map(([key, , value]) => `  ${key}: ${value},`),
    "};",
    "",
    `/** Reads \`${name}\` once per request in Server Components. */`,
    `export const ${name}Cache: ReturnType<typeof createSearchParamsCache<${map}>> = createSearchParamsCache(${name});`,
    "",
    `/** Parses \`${name}\` from a URL, a \`Request\` or \`searchParams\`. */`,
    `export const load${pascal(name)}: LoaderFunction<${map}> = createLoader(${name});`,
    "",
    `/** Writes \`${name}\` into a URL, for links. */`,
    `export const serialize${pascal(name)}: ReturnType<typeof createSerializer<${map}>> = createSerializer(${name});`,
  ];
}

/**
 * Search-param parsers for nuqs, one set per table list: a filter for every
 * column with a closed set of values, `orderBy` over the sortable columns,
 * `direction`, `cursor` and `limit`, with a cache, a loader and a serializer.
 * The file imports `nuqs/server`, which the app installs.
 */
export function nuqs(options: NuqsGeneratorOptions = {}): Generator {
  return {
    apiVersion: 1,
    name: "nuqs",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "nuqs.ts");

      const wanted =
        options.tables === undefined ? undefined : new Set(options.tables);

      const tables = input.model.tables
        .filter((table) => wanted === undefined || wanted.has(table.key))
        .toSorted((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));

      const missing = [...(wanted ?? [])].filter(
        (key) => !tables.some((table) => table.key === key),
      );

      if (missing.length > 0) {
        throw new Error(
          `nuqs(): no table named ${missing.map((key) => `"${key}"`).join(", ")}`,
        );
      }

      const contents = [
        HEADER,
        'import type { LoaderFunction, SingleParserBuilder } from "nuqs/server";',
        'import { createLoader, createSearchParamsCache, createSerializer, parseAsInteger, parseAsString, parseAsStringLiteral } from "nuqs/server";',
        ...tables.flatMap((table) => tableLines(table, options.limit ?? 25)),
        "",
      ].join("\n");

      return [{ path, contents }];
    },
  };
}
