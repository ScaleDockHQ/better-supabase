import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { Model } from "./model.ts";

import { GENERATED_HEADER } from "./emit.ts";
import { identifier, q } from "./shared.ts";

/** Folder of the per-table modules, next to the main generated module. */
const TABLES_DIR = "tables";

/** One generated `tables/<table>.ts`. */
export interface TableModuleInfo {
  /** App key of the table (`customerTags`). */
  readonly key: string;
  /** The module's export: the key with a `Table` suffix (`customerTagsTable`). */
  readonly name: string;
  /** Import path from the main generated module, with its extension. */
  readonly specifier: string;
  /** Path relative to the main generated module's folder. */
  readonly file: string;
}

/**
 * The module of each table, named after the database table. Two tables with the
 * same name in different schemas get the schema as a prefix.
 */
export function tableModules(model: Model): TableModuleInfo[] {
  const tables = Object.values(model.meta.tables);
  const counts = new Map<string, number>();

  for (const table of tables) {
    counts.set(table.name, (counts.get(table.name) ?? 0) + 1);
  }

  return tables.map((table) => {
    // Kebab-case, as every generated file name is.
    const base = identifier(
      (counts.get(table.name) ?? 0) > 1
        ? `${table.schema}_${table.name}`
        : table.name,
    ).replaceAll("_", "-");

    return {
      key: table.key,
      name: `${identifier(table.key)}Table`,
      specifier: `./${TABLES_DIR}/${base}.ts`,
      file: `${TABLES_DIR}/${base}.ts`,
    };
  });
}

/**
 * `tables/<table>.ts`: the table's runtime metadata and nothing else, as one
 * annotated call, so a bundler keeps it only for a page that imports it.
 */
export function emitTableModules(
  model: Model,
  modules: readonly TableModuleInfo[],
  config: Pick<ResolvedConfig, "output">,
  options: { readonly runtimeImport?: string } = {},
): GeneratedFile[] {
  const runtime = options.runtimeImport ?? "better-supabase";
  const folder = posix.dirname(config.output);

  return modules.map((module) => {
    const meta = model.meta.tables[module.key];

    return {
      path: posix.join(folder, module.file),
      contents: [
        GENERATED_HEADER,
        "/* oxlint-disable */",
        "/* eslint-disable */",
        "",
        `import { defineTable } from ${q(runtime)};`,
        "",
        `export const ${module.name} = /*#__PURE__*/ defineTable(${JSON.stringify(meta)});`,
        "",
      ].join("\n"),
    };
  });
}
