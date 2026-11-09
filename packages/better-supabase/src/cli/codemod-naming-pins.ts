import type { ResolvedConfig } from "../config/index.ts";
import type { BlockSqlNames } from "../sql/context.ts";
import type { NamingRename } from "./codemod-naming.ts";

import { createModuleContext } from "../sql/context.ts";
import { SQL_MODULES } from "../sql/index.ts";
import { codeRanges } from "./code-ranges.ts";
import { closing as closingBrace } from "./codemod-config.ts";

/** One `blocks.<block>.columns.<table>.<column>` entry that keeps an old name. */
export interface ColumnPin {
  readonly block: string;
  readonly table: string;
  readonly column: string;
  /** The column's name before the rename, which the app's own table still has. */
  readonly name: string;
}

/**
 * The columns of the app's own tables that the rename table renames and that
 * still carry the old name. The block's new default would not find them, so the
 * feature that reads them would turn off (ADR 0580). Each entry pins the old
 * name in the config. `ownColumns` is the app's columns by `schema.table`.
 */
export function columnPins(
  config: Pick<ResolvedConfig, "blocks">,
  renames: readonly NamingRename[],
  ownTables: Readonly<Record<string, string>>,
  ownColumns: Readonly<Record<string, readonly string[]>>,
): readonly ColumnPin[] {
  const pins: ColumnPin[] = [];
  const modules = config.blocks;

  const namesOf = (module: string): BlockSqlNames | undefined =>
    SQL_MODULES[module]?.names;

  for (const block of Object.keys(modules)) {
    const names = namesOf(block);

    if (names === undefined) {
      continue;
    }

    let ctx: ReturnType<typeof createModuleContext>;

    try {
      ctx = createModuleContext(block, namesOf, { modules, ownTables });
    } catch {
      // A config this context can't validate alone is refused by the render.
      continue;
    }

    // SAFETY: a block config's `columns` maps logical tables to logical columns.
    const configured = (modules[block]?.columns ?? {}) as Readonly<
      Record<string, Readonly<Record<string, string | null> | undefined>>
    >;

    for (const table of ctx.appOwned) {
      const spec = names.tables[table];

      if (spec === undefined) {
        continue;
      }

      const parts = ctx.tableName(table);
      const has = ownColumns[`${parts.schema}.${parts.name}`];

      if (has === undefined) {
        continue;
      }

      for (const [column, to] of Object.entries(spec.columns)) {
        const rename = renames.find(
          (candidate) =>
            candidate.kind === "column" &&
            candidate.to === to &&
            candidate.table?.split(".").at(-1) === spec.name,
        );

        if (
          rename !== undefined &&
          configured[table]?.[column] === undefined &&
          has.includes(rename.from) &&
          !has.includes(rename.to)
        ) {
          pins.push({ block, table, column, name: rename.from });
        }
      }
    }
  }

  return pins;
}

/**
 * `text` with each pin added under `<block>: { columns: { <table>: { ... } }
 * }`, creating the `columns` and table objects it needs. Only code counts.
 * Returns the pins it found no block object for, which the user adds by hand.
 */
export function withColumnPins(
  text: string,
  pins: readonly ColumnPin[],
): { readonly text: string; readonly missed: readonly ColumnPin[] } {
  let out = text;
  const missed: ColumnPin[] = [];

  for (const pin of pins) {
    const ranges = codeRanges(out);

    const code = (index: number): boolean =>
      ranges.some(([start, end]) => index >= start && index < end);

    const block = new RegExp(
      `(?:^|[\\s,{])(?:"${pin.block}"|${pin.block})\\s*:\\s*\\{`,
      "g",
    );

    const found = [...out.matchAll(block)].find((match) =>
      code(match.index + match[0].length - 1),
    );

    if (found === undefined) {
      missed.push(pin);
      continue;
    }

    const open = found.index + found[0].length - 1;
    const end = closingBrace(out, open, code);
    const body = out.slice(open, end + 1);
    const entry = `${pin.column}: "${pin.name}"`;
    const columns = /\bcolumns\s*:\s*\{/.exec(body);

    if (columns === null) {
      out = `${out.slice(0, open + 1)} columns: { ${pin.table}: { ${entry} } },${out.slice(open + 1)}`;
      continue;
    }

    const columnsOpen = open + columns.index + columns[0].length - 1;
    const columnsEnd = closingBrace(out, columnsOpen, code);
    const inner = out.slice(columnsOpen, columnsEnd + 1);
    const table = new RegExp(`\\b${pin.table}\\s*:\\s*\\{`).exec(inner);

    if (table === null) {
      out = `${out.slice(0, columnsOpen + 1)} ${pin.table}: { ${entry} },${out.slice(columnsOpen + 1)}`;
      continue;
    }

    const tableOpen = columnsOpen + table.index + table[0].length - 1;
    out = `${out.slice(0, tableOpen + 1)} ${entry},${out.slice(tableOpen + 1)}`;
  }

  return { text: out, missed };
}

function tablePattern(rename: NamingRename): RegExp | undefined {
  const [schema, name] = rename.table?.split(".") ?? [];

  if (schema === undefined || name === undefined) {
    return undefined;
  }

  return new RegExp(
    String.raw`(?<![\w$"])"?${schema}"?\s*\.\s*"?${name}"?(?![\w$"])`,
    "i",
  );
}

/**
 * `sql` with the column names of the `column` rows renamed, in each statement
 * that names the renamed block table with its schema (`better_supabase.x`).
 * Statements about the app's own tables keep their names, and so does a table
 * in another schema. A string literal stays as it is.
 */
export function renameSqlColumns(
  sql: string,
  renames: readonly NamingRename[],
  skip: ReadonlySet<string> = new Set(),
): string {
  const columns = renames.filter(
    (rename) =>
      rename.kind === "column" &&
      rename.table !== undefined &&
      !skip.has(rename.from),
  );

  if (columns.length === 0 || !sql.includes("better_supabase")) {
    return sql;
  }

  return sql
    .split(/(?<=;)/)
    .map((statement) => {
      let out = statement;

      for (const rename of columns) {
        const table = tablePattern(rename);

        if (table === undefined || !table.test(out)) {
          continue;
        }

        out = out.replaceAll(
          new RegExp(
            String.raw`'(?:[^']|'')*'|(?<![\w$])("?)${rename.from}\1(?![\w$])`,
            "g",
          ),
          (whole, quote: string | undefined) =>
            whole.startsWith("'") ? whole : `${quote}${rename.to}${quote}`,
        );
      }

      return out;
    })
    .join("");
}
