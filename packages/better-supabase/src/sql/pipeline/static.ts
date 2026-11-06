import { maskComments, statementSpans } from "../over-app-tables.ts";
import { NAME, qualified } from "../schema-scan.ts";

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

/**
 * Drops a schema diff makes unnecessary: it removes what the files no longer
 * declare and replaces what changed.
 */
const DROP = /^drop\s+(?:policy|trigger|function|index|view)\s+if\s+exists\b/i;

const DROP_CONSTRAINT = new RegExp(
  String.raw`^alter\s+table\s+(?:only\s+)?${TABLE_NAME}\s+drop\s+constraint\s+if\s+exists\s+${NAME}(?:\s+cascade)?$`,
  "i",
);

const CREATE_TABLE = new RegExp(
  String.raw`^(create\s+(?:unlogged\s+)?table\s+)if\s+not\s+exists\s+(${TABLE_NAME})`,
  "i",
);

const CREATE_INDEX = new RegExp(
  String.raw`^(create\s+(?:unique\s+)?index\s+)(?:concurrently\s+)?if\s+not\s+exists\s+(${NAME}\s+on\s+(?:only\s+)?(${TABLE_NAME}))`,
  "i",
);

const ALTER_TABLE = new RegExp(
  String.raw`^(alter\s+table\s+(?:only\s+)?)(${TABLE_NAME})(\s+)([\s\S]+)$`,
  "i",
);

const CREATE_TABLE_BODY = new RegExp(
  String.raw`^create\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(${TABLE_NAME})\s*\(`,
  "i",
);

const CONSTRAINT_WORD =
  /^(?:constraint|check|unique|primary|foreign|exclude|like)\b/i;

const COLUMN = new RegExp(String.raw`^(${NAME})`);

/** `text` split at the commas outside parentheses, quotes and dollar quotes. */
function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let start = 0;
  let quote = "";

  for (let at = 0; at < text.length; at += 1) {
    const char = text[at]!;

    if (quote !== "") {
      if (char === quote) {
        quote = "";
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      parts.push(text.slice(start, at));
      start = at + 1;
    }
  }

  return [...parts, text.slice(start)];
}

const unquoted = (name: string): string =>
  name.startsWith('"') ? name.slice(1, -1).replaceAll('""', '"') : name;

/** The columns a `create table` statement declares, by table. */
function createdColumns(
  statements: readonly string[],
): Map<string, Set<string>> {
  const tables = new Map<string, Set<string>>();

  for (const statement of statements) {
    const head = CREATE_TABLE_BODY.exec(statement);

    if (head === null) {
      continue;
    }

    const open = head[0].length - 1;
    let depth = 0;
    let close = -1;

    for (let at = open; at < statement.length; at += 1) {
      if (statement[at] === "(") {
        depth += 1;
      } else if (statement[at] === ")") {
        depth -= 1;

        if (depth === 0) {
          close = at;
          break;
        }
      }
    }

    if (close === -1) {
      continue;
    }

    const columns = new Set<string>();

    for (const item of splitTopLevel(statement.slice(open + 1, close))) {
      const trimmed = item.trim();

      const name = CONSTRAINT_WORD.test(trimmed)
        ? undefined
        : COLUMN.exec(trimmed)?.[1];

      if (name !== undefined) {
        columns.add(unquoted(name));
      }
    }

    tables.set(qualified(head[1]!), columns);
  }

  return tables;
}

const ADD_COLUMN = new RegExp(
  String.raw`^add\s+column\s+(?:if\s+not\s+exists\s+)?(${NAME})(?![\w$"])`,
  "i",
);

/**
 * `add column` clauses as static DDL: `if not exists` goes away on a table the
 * block owns, and a column the same file's `create table` declares is not added
 * again. An app table keeps `if not exists`, since the app's files may declare
 * the column and the block can't see them all.
 */
function staticAlter(
  statement: string,
  created: ReadonlyMap<string, ReadonlySet<string>>,
  appTables: ReadonlySet<string>,
  keepIfNotExists: boolean,
): string | undefined {
  const match = ALTER_TABLE.exec(statement);

  if (match === null) {
    return statement;
  }

  const table = qualified(match[2]!);
  const app = keepIfNotExists || appTables.has(table);
  const clauses = splitTopLevel(match[4]!).map((clause) => clause.trim());

  if (!clauses.every((clause) => ADD_COLUMN.test(clause))) {
    return statement;
  }

  const kept = clauses.flatMap((clause) => {
    const name = unquoted(ADD_COLUMN.exec(clause)![1]!);

    if (!app && created.get(table)?.has(name) === true) {
      return [];
    }

    return [
      app
        ? clause.replace(
            /^add\s+column\s+(?!if\s+not\s+exists)/i,
            "add column if not exists ",
          )
        : clause.replace(
            /^add\s+column\s+if\s+not\s+exists\s+/i,
            "add column ",
          ),
    ];
  });

  return kept.length === 0
    ? undefined
    : `${match[1]}${match[2]}${match[3]}${kept.join(",\n  ")}`;
}

/**
 * `sql` as declarative DDL, which a schema diff reads: no `drop ... if exists`
 * of a policy, trigger, function, index or constraint, and no `if not exists`
 * on tables, indexes or the columns of tables the block owns. Statements inside
 * a function or a `do` block stay as they are. An object on a table in
 * `appTables` keeps its `if not exists`, because an app file may declare it.
 */
export function staticDdl(
  sql: string,
  appTables: ReadonlySet<string> = new Set(),
  options: { readonly keepIfNotExists?: boolean } = {},
): string {
  const spans = statementSpans(sql);

  const texts = spans.map(([from, to]) => {
    const masked = maskComments(sql.slice(from, to));
    const lead = /^\s*/.exec(masked)![0].length;

    return { lead, text: masked.slice(lead).replace(/;$/, "").trim() };
  });

  const created = createdColumns(texts.map((entry) => entry.text));

  return spans
    .map(([from, to], index) => {
      const original = sql.slice(from, to);
      const { lead, text } = texts[index]!;
      const prefix = original.slice(0, lead);
      const semicolon = original.endsWith(";") ? ";" : "";

      if (DROP.test(text) || DROP_CONSTRAINT.test(text)) {
        return prefix.trim() === "" ? "" : prefix.replace(/\s+$/, "\n");
      }

      const body = original.slice(lead).replace(/;$/, "");

      const table = CREATE_TABLE.exec(text);

      if (
        table !== null &&
        options.keepIfNotExists !== true &&
        !appTables.has(qualified(table[2]!))
      ) {
        return `${prefix}${body.replace(/^(create\s+(?:unlogged\s+)?table\s+)if\s+not\s+exists\s+/i, "$1")}${semicolon}`;
      }

      const indexed = CREATE_INDEX.exec(text);

      if (
        indexed !== null &&
        options.keepIfNotExists !== true &&
        !appTables.has(qualified(indexed[3]!))
      ) {
        return `${prefix}${body.replace(/^(create\s+(?:unique\s+)?index\s+)(?:concurrently\s+)?if\s+not\s+exists\s+/i, "$1")}${semicolon}`;
      }

      const altered = staticAlter(
        text,
        created,
        appTables,
        options.keepIfNotExists === true,
      );

      if (altered === undefined) {
        return prefix.trim() === "" ? "" : prefix.replace(/\s+$/, "\n");
      }

      return altered === text ? original : `${prefix}${altered}${semicolon}`;
    })
    .join("");
}

const CREATE_POLICY = new RegExp(
  String.raw`^create\s+policy\s+(${NAME})\s+on\s+(${TABLE_NAME})`,
  "i",
);

const CREATE_TRIGGER = new RegExp(
  String.raw`^create\s+(?:constraint\s+)?trigger\s+(${NAME})\b[\s\S]*?\bon\s+(${TABLE_NAME})`,
  "i",
);

const ADD_CONSTRAINT = new RegExp(
  String.raw`^alter\s+table\s+(?:only\s+)?(${TABLE_NAME})\s+add\s+constraint\s+(${NAME})\b`,
  "i",
);

/**
 * `sql` that runs again: a `drop` before each policy, trigger and constraint
 * the file creates and `if not exists` on each column it adds. The migrations
 * workflow writes every module into each migration, so each statement a
 * migration repeats must be safe to repeat.
 */
export function rerunnableDdl(sql: string): string {
  return statementSpans(sql)
    .map(([from, to]) => {
      const original = sql.slice(from, to);
      const masked = maskComments(original);
      const lead = /^\s*/.exec(masked)![0].length;
      const text = masked.slice(lead);
      const head = original.slice(0, lead);
      const rest = original.slice(lead);
      const policy = CREATE_POLICY.exec(text);
      const trigger = CREATE_TRIGGER.exec(text);
      const constraint = ADD_CONSTRAINT.exec(text);

      if (policy !== null) {
        return `${head}drop policy if exists ${policy[1]} on ${policy[2]};\n${rest}`;
      }

      if (trigger !== null) {
        return `${head}drop trigger if exists ${trigger[1]} on ${trigger[2]};\n${rest}`;
      }

      if (constraint !== null) {
        return `${head}alter table ${constraint[1]} drop constraint if exists ${constraint[2]};\n${rest}`;
      }

      const altered = ALTER_TABLE.exec(text);

      if (
        altered !== null &&
        /^add\s+column\s+(?!if\s+not\s+exists)/i.test(altered[4]!.trim())
      ) {
        return `${head}${rest.replaceAll(/\badd\s+column\s+(?!if\s+not\s+exists)/gi, "add column if not exists ")}`;
      }

      return original;
    })
    .join("");
}
