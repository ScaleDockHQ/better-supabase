import {
  closingParen,
  indexStatements,
  NAME,
  qualified,
  splitTopLevel,
  TABLE,
} from "./schema-scan.ts";

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

/** Comments replaced by spaces, so offsets into `text` stay the same. */
export function maskComments(text: string): string {
  return text
    .replaceAll(/--[^\n]*/g, (comment) => " ".repeat(comment.length))
    .replaceAll(/\/\*[\s\S]*?\*\//g, (comment) =>
      comment.replaceAll(/[^\n]/g, " "),
    );
}

/**
 * The name `ctx.col` gives a column of the app's table that the block maps to
 * `null`, so the table's DDL still renders; `withoutUnmappedColumns` drops it.
 */
export const UNMAPPED_COLUMN = "bsb_unmapped:";

const UNMAPPED_DDL = new RegExp(
  String.raw`^[ \t]*(?:alter table [^;\n]* add column if not exists|create (?:unique )?index [^;]*?)[^;]*"${UNMAPPED_COLUMN}[^;]*;\n?`,
  "gim",
);

const UNMAPPED_USE = new RegExp(
  String.raw`"${UNMAPPED_COLUMN}([^".]+)\.([^"]+)"`,
);

/**
 * `sql` without the column additions and indexes for columns of the app's
 * tables that the block maps to `null`. Any other use of such a column throws,
 * since the block needs it.
 */
export function withoutUnmappedColumns(sql: string, instance: string): string {
  const out = sql.replaceAll(UNMAPPED_DDL, "");
  const use = UNMAPPED_USE.exec(out);

  if (use !== null) {
    throw new TypeError(
      `Module "${instance}" needs ${use[1]}.${use[2]}, which blocks.${instance}.columns maps to null`,
    );
  }

  return out;
}

/**
 * The table name `ctx.table` gives a table the block maps to `null` while it
 * runs over the app's tables; `withoutUnmappedTables` drops what builds it.
 */
export const UNMAPPED_TABLE = "bsb_unmapped_table:";

const DOLLAR_TAG = /\$(?:[A-Za-z_]\w*)?\$/y;

/** The end of the quoted or commented text that starts at `at`, or `at`. */
function skipQuoted(sql: string, at: number): number {
  const char = sql[at];

  if (sql.startsWith("--", at)) {
    const end = sql.indexOf("\n", at);

    return end === -1 ? sql.length : end;
  }

  if (sql.startsWith("/*", at)) {
    const end = sql.indexOf("*/", at + 2);

    return end === -1 ? sql.length : end + 2;
  }

  if (char === "'" || char === '"') {
    let end = at + 1;

    while (end < sql.length) {
      if (sql[end] === char && sql[end + 1] === char) {
        end += 2;
      } else if (sql[end] === char) {
        return end + 1;
      } else {
        end += 1;
      }
    }

    return end;
  }

  if (char === "$") {
    DOLLAR_TAG.lastIndex = at;
    const tag = DOLLAR_TAG.exec(sql)?.[0];

    if (tag !== undefined) {
      const end = sql.indexOf(tag, at + tag.length);

      return end === -1 ? sql.length : end + tag.length;
    }
  }

  return at;
}

/** Each statement of `sql` with what precedes it, up to its semicolon. */
export function statementSpans(sql: string): [number, number][] {
  const spans: [number, number][] = [];
  let start = 0;
  let at = 0;

  while (at < sql.length) {
    const skipped = skipQuoted(sql, at);

    if (skipped !== at) {
      at = skipped;
    } else if (sql[at] === ";") {
      spans.push([start, at + 1]);
      start = at + 1;
      at += 1;
    } else {
      at += 1;
    }
  }

  return start < sql.length ? [...spans, [start, sql.length]] : spans;
}

const UNMAPPED_TABLE_DDL = new RegExp(
  String.raw`^\s*(?:create\s+(?:unique\s+)?index|create\s+policy|drop\s+policy|create\s+(?:or\s+replace\s+)?trigger|drop\s+trigger|alter\s+table|grant|revoke|comment\s+on|create\s+table\s+(?:if\s+not\s+exists\s+)?\S*${UNMAPPED_TABLE})`,
  "i",
);

const UNMAPPED_TABLE_USE = new RegExp(String.raw`${UNMAPPED_TABLE}(\w+)`);

/**
 * `sql` without the statements that build or change the tables the block maps
 * to `null`. Any other use of such a table throws, since the block needs it.
 */
export function withoutUnmappedTables(sql: string, instance: string): string {
  if (!sql.includes(UNMAPPED_TABLE)) {
    return sql;
  }

  const out = statementSpans(sql)
    .map(([from, to]) => sql.slice(from, to))
    .filter(
      (statement) =>
        !statement.includes(UNMAPPED_TABLE) ||
        !UNMAPPED_TABLE_DDL.test(maskComments(statement)),
    )
    .join("");

  const use = UNMAPPED_TABLE_USE.exec(out);

  if (use !== null) {
    throw new TypeError(
      `Module "${instance}" needs table "${use[1]}", which blocks.${instance}.tables maps to null`,
    );
  }

  return out;
}

const ALTER_CONSTRAINT = /* @__PURE__ */ new RegExp(
  String.raw`^[ \t]*alter\s+table\s+(?:only\s+)?(${TABLE_NAME})\s+(?:add\s+constraint|drop\s+constraint|validate\s+constraint|alter\s+column)\b[^;]*;[ \t]*\n?`,
  "gim",
);

const REVOKE = /* @__PURE__ */ new RegExp(
  String.raw`^[ \t]*revoke\s[^;]*?\son\s+(?:table\s+)?(${TABLE_NAME})\s+from\b[^;]*;[ \t]*\n?`,
  "gim",
);

const ENSURE_CHECK =
  /^do \$\$\nbegin\n {2}if coalesce\(obj_description\(\(\n\s+select c\.oid from pg_catalog\.pg_constraint c\n\s+where c\.conrelid = '([^']+)'::regclass[\s\S]*?\n\$\$;\n?/gm;

/**
 * `sql` without the statements that would change the data rules or access of
 * the app's tables: checks and other constraints, column alterations and
 * revokes. Columns, RLS, grants, policies, triggers and indexes stay.
 */
export function withoutAppTableEdits(
  sql: string,
  appTables: ReadonlySet<string>,
): string {
  if (appTables.size === 0) {
    return sql;
  }

  const drop = (statement: string, table: string) =>
    appTables.has(qualified(table)) ? "" : statement;

  return sql
    .replaceAll(ALTER_CONSTRAINT, drop)
    .replaceAll(REVOKE, drop)
    .replaceAll(ENSURE_CHECK, drop);
}

/**
 * The relation a DDL statement builds or changes: its table, index, grant,
 * policy, trigger or comment target.
 */
const DDL_TARGETS: readonly RegExp[] = [
  new RegExp(
    String.raw`^\s*create\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(${TABLE_NAME})`,
    "i",
  ),
  new RegExp(
    String.raw`^\s*alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${TABLE_NAME})`,
    "i",
  ),
  new RegExp(
    String.raw`^\s*create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:${NAME}\s+)?on\s+(?:only\s+)?(${TABLE_NAME})`,
    "i",
  ),
  new RegExp(
    String.raw`^\s*(?:grant|revoke)\s[^;]*?\bon\s+(?:table\s+)?(${TABLE_NAME})\s+(?:to|from)\b`,
    "i",
  ),
  new RegExp(
    String.raw`^\s*(?:create|alter|drop)\s+policy\s+(?:if\s+exists\s+)?${NAME}\s+on\s+(${TABLE_NAME})`,
    "i",
  ),
  new RegExp(
    String.raw`^\s*create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+${NAME}\s[^;]*?\bon\s+(${TABLE_NAME})`,
    "i",
  ),
  new RegExp(
    String.raw`^\s*drop\s+trigger\s+(?:if\s+exists\s+)?${NAME}\s+on\s+(${TABLE_NAME})`,
    "i",
  ),
  new RegExp(String.raw`^\s*comment\s+on\s+table\s+(${TABLE_NAME})`, "i"),
  new RegExp(
    String.raw`^\s*comment\s+on\s+column\s+(${TABLE_NAME})\s*\.\s*${NAME}`,
    "i",
  ),
];

/**
 * `sql` without the statements that build or change the app's views in `views`
 * (as `schema.view`): their `create table`, columns, constraints, indexes, row
 * level security, grants, revokes, policies, triggers and comments. The
 * functions that read the views stay.
 */
export function overAppViews(sql: string, views: ReadonlySet<string>): string {
  if (views.size === 0) {
    return sql;
  }

  const said = new Set<string>();

  return statementSpans(sql)
    .map(([from, to]) => {
      const statement = sql.slice(from, to);
      const masked = maskComments(statement);

      const target = DDL_TARGETS.map(
        (pattern) => pattern.exec(masked)?.[1],
      ).find((match) => match !== undefined);

      const view = target === undefined ? undefined : qualified(target);

      if (view === undefined || !views.has(view)) {
        return statement;
      }

      const lead = /^\s*/.exec(statement)![0];

      if (said.has(view)) {
        return "";
      }

      said.add(view);

      return `${lead}-- ${view} is the app's view: this block writes only the functions that read it.`;
    })
    .join("");
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
      .filter((part) => !part.startsWith(`"${UNMAPPED_COLUMN}`))
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

/**
 * `sql` without the plain btree indexes it creates on the app's tables in
 * `appTables` that an index in `ownIndexes` already covers: one whose leading
 * columns are the same. Unique and partial indexes stay.
 */
export function withoutCoveredIndexes(
  sql: string,
  appTables: ReadonlySet<string>,
  ownIndexes: Readonly<Record<string, readonly (readonly string[])[]>> = {},
): string {
  if (appTables.size === 0 || Object.keys(ownIndexes).length === 0) {
    return sql;
  }

  return statementSpans(sql)
    .map(([from, to]) => {
      const statement = sql.slice(from, to);
      const [index] = indexStatements(maskComments(statement));

      if (
        index === undefined ||
        !appTables.has(index.table) ||
        index.unique ||
        index.partial ||
        !index.plain ||
        index.method !== "btree"
      ) {
        return statement;
      }

      const covered = (ownIndexes[index.table] ?? []).some(
        (columns) =>
          columns.length >= index.columns.length &&
          index.columns.every((column, at) => columns[at] === column),
      );

      if (!covered) {
        return statement;
      }

      const lead = /^\s*/.exec(statement)![0];

      return `${lead}-- ${index.table} already has an index on (${index.columns.join(", ")}), so this block adds none.`;
    })
    .join("");
}
