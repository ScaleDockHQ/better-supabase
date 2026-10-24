import {
  closingParen,
  qualified,
  splitTopLevel,
  TABLE,
} from "./schema-scan.ts";

/** Comments replaced by spaces, so offsets into `text` stay the same. */
function maskComments(text: string): string {
  return text
    .replaceAll(/--[^\n]*/g, (comment) => " ".repeat(comment.length))
    .replaceAll(/\/\*[\s\S]*?\*\//g, (comment) =>
      comment.replaceAll(/[^\n]/g, " "),
    );
}

const COLUMN_NAME = /^("(?:[^"]|"")+"|[a-z_][\w$]*)/i;

const TABLE_CONSTRAINT =
  /^(constraint|check|unique|primary|foreign|exclude|like)\b/i;

function unquote(name: string): string {
  return name.startsWith('"') ? name.slice(1, -1).replaceAll('""', '"') : name;
}

/**
 * A column definition as it can be added to a table that has rows: without
 * `primary key` or `unique`, and nullable unless it has a default.
 */
function addable(definition: string): string {
  const column = definition
    .replaceAll(/\s+primary\s+key\b/gi, "")
    .replaceAll(/\s+unique\b(?!\s*\()/gi, "");

  const nullable = /\b(?:default|generated)\b/i.test(column)
    ? column
    : column.replaceAll(/\s+not\s+null\b/gi, "");

  return nullable.replaceAll(/\s+/g, " ").trim();
}

/**
 * `sql` with the `create table` statement of each table in `appTables` (as
 * `schema.table`) replaced by `alter table ... add column if not exists` for
 * the columns it declares. `appColumns` lists the columns the app's table
 * already has, when known, so only the missing ones are added.
 */
export function overAppTables(
  sql: string,
  appTables: ReadonlySet<string>,
  appColumns: Readonly<Record<string, readonly string[]>> = {},
): string {
  if (appTables.size === 0) {
    return sql;
  }

  const masked = maskComments(sql);
  let out = "";
  let at = 0;

  for (const match of masked.matchAll(TABLE)) {
    const table = qualified(match[1]!);

    if (!appTables.has(table) || match.index < at) {
      continue;
    }

    const open = match.index + match[0].length - 1;
    const close = closingParen(masked, open);
    const end = close === -1 ? -1 : masked.indexOf(";", close);

    if (end === -1) {
      continue;
    }

    const has = new Set(appColumns[table]);
    const name = match[1]!.trim();

    const columns = splitTopLevel(masked.slice(open + 1, close))
      .map((part) => part.trim())
      .filter((part) => part !== "" && !TABLE_CONSTRAINT.test(part))
      .filter((part) => {
        const column = COLUMN_NAME.exec(part)?.[0];

        return column !== undefined && !has.has(unquote(column));
      });

    const added =
      columns.length === 0
        ? `-- ${table} is the app's table, and it has every column this block needs.`
        : [
            `-- ${table} is the app's table: this block adds only the columns it needs.`,
            ...columns.map(
              (column) =>
                `alter table ${name} add column if not exists ${addable(column)};`,
            ),
          ].join("\n");

    out += sql.slice(at, match.index) + added;
    at = end + 1;
  }

  return out + sql.slice(at);
}
