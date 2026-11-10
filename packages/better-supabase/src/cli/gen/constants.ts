import { posix } from "node:path";

import type { GeneratedFile } from "../../config/index.ts";
import type { Model } from "./model.ts";

import { GENERATED_HEADER, valueLists } from "./emit.ts";
import { identifier, pascal, q } from "./shared.ts";

/** The two modules `gen.constants` writes, next to the generated module. */
export function emitConstants(
  model: Model,
  output: string,
): readonly GeneratedFile[] {
  const dir = posix.dirname(output);
  const at = (name: string): string => (dir === "." ? name : `${dir}/${name}`);

  return [
    { path: at("enums.ts"), contents: emitEnums(model) },
    { path: at("columns.ts"), contents: emitColumns(model) },
  ];
}

const PREAMBLE = [
  GENERATED_HEADER,
  "/* oxlint-disable */",
  "/* eslint-disable */",
  "",
];

/**
 * Every enum and every CHECK value list as a constant array and its union type,
 * with no import, so a browser form or a script reads them without the runtime
 * package.
 */
function emitEnums(model: Model): string {
  const seen = new Map<string, string>();
  const lines: string[] = [...PREAMBLE];

  for (const list of valueLists(model)) {
    for (const name of [list.constant, list.typeName]) {
      const other = seen.get(name);

      if (other !== undefined) {
        throw new TypeError(
          `${list.source} and ${other} both export "${name}" from enums.ts. Rename one of them in the database.`,
        );
      }

      seen.set(name, list.source);
    }

    lines.push(
      `export const ${list.constant} = [${list.values.map(q).join(", ")}] as const;`,
      `export type ${list.typeName} = (typeof ${list.constant})[number];`,
    );
  }

  if (seen.size === 0) {
    lines.push("export {};");
  }

  return `${lines.join("\n")}\n`;
}

/**
 * One constant per table: each column's name in the rows (the configured
 * casing) to its database name, which `$client`, `queryRaw` and SQL use.
 */
function emitColumns(model: Model): string {
  const lines: string[] = [...PREAMBLE];

  for (const table of model.tables) {
    const name = identifier(`${table.key}Columns`);

    lines.push(
      `export const ${name} = {`,
      ...table.columns.map((column) => `  ${q(column.app)}: ${q(column.db)},`),
      "} as const;",
      `export type ${identifier(`${pascal(table.key)}Column`)} = keyof typeof ${name};`,
    );
  }

  if (model.tables.length === 0) {
    lines.push("export {};");
  }

  return `${lines.join("\n")}\n`;
}
