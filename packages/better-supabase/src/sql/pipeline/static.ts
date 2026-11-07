import { maskComments, statementSpans } from "../over-app-tables.ts";
import { closingParen, NAME, qualified } from "../schema-scan.ts";

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

const ADD_CHECK = new RegExp(
  String.raw`^alter\s+table\s+(?:only\s+)?(${TABLE_NAME})\s+add\s+constraint\s+(${NAME})\s+check\s*\(([\s\S]*)\)$`,
  "i",
);

/** The ranges of `text` between the commas outside parentheses and quotes. */
function splitRanges(text: string): [number, number][] {
  const ranges: [number, number][] = [];
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
      ranges.push([start, at]);
      start = at + 1;
    }
  }

  return [...ranges, [start, text.length]];
}

/** `text` split at the commas outside parentheses and quotes. */
const splitTopLevel = (text: string): string[] =>
  splitRanges(text).map(([from, to]) => text.slice(from, to));

const unquoted = (name: string): string =>
  name.startsWith('"') ? name.slice(1, -1).replaceAll('""', '"') : name;

/** One `create table` statement of the file. */
interface CreatedTable {
  /** The statement's index among the file's statements. */
  readonly index: number;
  readonly columns: Set<string>;
  /** The body with its whitespace collapsed. */
  readonly body: string;
  /** Offsets of the opening and closing parenthesis in the statement. */
  readonly open: number;
  readonly close: number;
}

function createdTables(
  statements: readonly string[],
): Map<string, CreatedTable> {
  const tables = new Map<string, CreatedTable>();

  for (const [index, statement] of statements.entries()) {
    const head = CREATE_TABLE_BODY.exec(statement);

    if (head === null) {
      continue;
    }

    const open = head[0].length - 1;
    const close = closingParen(statement, open);

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

    tables.set(qualified(head[1]!), {
      index,
      columns,
      body: statement.slice(open + 1, close).replaceAll(/\s+/g, " "),
      open,
      close,
    });
  }

  return tables;
}

const NAMED_CONSTRAINT = new RegExp(String.raw`^constraint\s+(${NAME})\b`, "i");

/**
 * What an item of a `create table` body is called for a replacement: a column
 * by its name, a named constraint as `constraint:<name>`, the table's unnamed
 * check as `""`.
 */
function itemKey(item: string): string | undefined {
  const trimmed = item.trim();
  const named = NAMED_CONSTRAINT.exec(trimmed)?.[1];

  if (named !== undefined) {
    return `constraint:${unquoted(named)}`;
  }

  if (CONSTRAINT_WORD.test(trimmed)) {
    return /^check\b/i.test(trimmed) ? "" : undefined;
  }

  return unquoted(COLUMN.exec(trimmed)?.[1] ?? "");
}

/** Whether every quoted identifier of `expression` names one of `columns`. */
function readsOnly(expression: string, columns: ReadonlySet<string>): boolean {
  const outside = expression.replaceAll(/'(?:[^']|'')*'/g, "''");

  return [...outside.matchAll(/"((?:[^"]|"")+)"/g)].every((match) =>
    columns.has(match[1]!.replaceAll('""', '"')),
  );
}

/** Whether the column `key` (or, for `""`, the table) has an inline check. */
function hasInlineCheck(
  statement: string,
  table: CreatedTable,
  key: string,
): boolean {
  const body = statement.slice(table.open + 1, table.close);

  return splitTopLevel(body).some(
    (item) => itemKey(item) === key && /\bcheck\s*\(/i.test(item),
  );
}

/**
 * `statement` (a `create table`, with `lead` characters of comments before it
 * in `original`) with the inline check of a column, or the table's own unnamed
 * check, replaced by the expression a later `add constraint` of the auto name
 * would have written. A schema diff holds one check per name, so the file
 * declares the one that wins.
 */
function withInlineChecks(
  original: string,
  masked: string,
  table: CreatedTable,
  lead: number,
  overrides: ReadonlyMap<string, string | null>,
): string {
  const bodyMasked = masked.slice(table.open + 1, table.close);
  const start = lead + table.open + 1;
  let out = original;
  const ranges = splitRanges(bodyMasked);

  for (const [at, [from, to]] of ranges.entries().toArray().toReversed()) {
    const item = bodyMasked.slice(from, to);
    const key = itemKey(item);
    const expression = key === undefined ? undefined : overrides.get(key);

    if (expression === undefined) {
      continue;
    }

    if (expression === null) {
      // The check reads a column a later statement adds, so the `create table`
      // drops it and the `add constraint` stays after that column.
      const own = key === "" || key?.startsWith("constraint:") === true;

      if (own) {
        const last = at === ranges.length - 1;

        const trailing = item.length - item.trimEnd().length;

        const [cutFrom, cutTo] = last
          ? at > 0
            ? [ranges[at - 1]![1], to - trailing]
            : [from, to - trailing]
          : [from, to + 1];

        out = `${out.slice(0, start + cutFrom)}${out.slice(start + cutTo)}`;
      } else {
        const opens = [...item.matchAll(/\bcheck\s*\(/gi)];
        const final = opens.at(-1);

        if (final !== undefined) {
          const open = final.index + final[0].length - 1;
          const close = closingParen(item, open);

          if (close !== -1) {
            const before = item.slice(0, final.index);
            const keep = before.length - before.trimEnd().length;

            out = `${out.slice(0, start + from + final.index - keep)}${out.slice(start + from + close + 1)}`;
          }
        }
      }

      continue;
    }

    const opens = [...item.matchAll(/\bcheck\s*\(/gi)];
    const last = opens.at(-1);

    if (last === undefined) {
      continue;
    }

    const open = last.index + last[0].length - 1;
    const close = closingParen(item, open);

    if (close === -1) {
      continue;
    }

    out = `${out.slice(0, start + from + open + 1)}${expression}${out.slice(start + from + close)}`;
  }

  return out;
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
  created: ReadonlyMap<string, CreatedTable>,
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

    if (!app && created.get(table)?.columns.has(name) === true) {
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

/** The Supabase-owned tables a block writes policies on; they always exist. */
const PLATFORM_TABLES = "realtime\\.messages|storage\\.objects";

const GUARDED_PLATFORM_DO = new RegExp(
  String.raw`^do\s+(\$\w*\$)\s*begin\s+if\s+to_regclass\('(?:${PLATFORM_TABLES})'\)\s+is\s+not\s+null\s+then([\s\S]*?)end\s+if;\s*end;?\s*\1$`,
  "i",
);

const DUPLICATE_OBJECT_DO =
  /^do\s+(\$\w*\$)\s*begin\s+(create\s+type\s[\s\S]*?;)\s*exception\s+when\s+duplicate_object\s+then\s+null;\s*end\s*;?\s*\1$/i;

/**
 * `sql` with the `do` blocks that only guard one statement written out: a
 * policy on a Supabase-owned table (`realtime.messages`, `storage.objects`,
 * which every project has) and a `create type` that swallows
 * `duplicate_object`. The choice the block made at run time is made here.
 */
export function unwrapGuards(
  sql: string,
  options: { readonly types?: boolean } = {},
): string {
  return statementSpans(sql)
    .map(([from, to]) => {
      const original = sql.slice(from, to);
      const masked = maskComments(original);
      const lead = /^\s*/.exec(masked)![0].length;
      const text = masked.slice(lead).replace(/;$/, "").trim();
      const head = original.slice(0, lead);
      const guarded = GUARDED_PLATFORM_DO.exec(text);

      if (guarded !== null) {
        const body = guarded[2]!
          .trim()
          .split("\n")
          .map((line) =>
            /^\s+(?:create|drop|alter|grant|revoke)\s/i.test(line)
              ? line.trim()
              : line,
          )
          .join("\n");

        return `${head}${body}`;
      }

      const created =
        options.types === false ? null : DUPLICATE_OBJECT_DO.exec(text);

      return created === null ? original : `${head}${created[2]!.trim()}`;
    })
    .join("");
}

/**
 * `sql` without a second `create trigger` or `create policy` of the same name
 * on the same table. Two entities of one block can adopt one app table, and
 * each emits the triggers and policies the table needs.
 */
function withoutRepeatedObjects(sql: string): string {
  const seen = new Set<string>();

  return statementSpans(sql)
    .map(([from, to]) => {
      const original = sql.slice(from, to);
      const masked = maskComments(original);
      const text = masked.slice(/^\s*/.exec(masked)![0].length);
      const named = CREATE_TRIGGER.exec(text) ?? CREATE_POLICY.exec(text);

      if (named === null) {
        return original;
      }

      const key = `${text.slice(0, 14).toLowerCase()} ${named[1]!} ${named[2]!}`;

      if (seen.has(key)) {
        return "";
      }

      seen.add(key);

      return original;
    })
    .join("");
}

/**
 * `sql` as declarative DDL, which a schema diff reads: no `drop ... if exists`
 * of a policy, trigger, function, index or constraint, and no `if not exists`
 * on tables, indexes or the columns of tables the block owns. Statements inside
 * a function or a `do` block stay as they are. An object on a table in
 * `appTables` keeps its `if not exists`, because an app file may declare it.
 */
export function staticDdl(
  source: string,
  appTables: ReadonlySet<string> = new Set(),
  options: { readonly keepIfNotExists?: boolean } = {},
): string {
  return withoutRepeatedObjects(staticStatements(source, appTables, options));
}

function staticStatements(
  source: string,
  appTables: ReadonlySet<string> = new Set(),
  options: { readonly keepIfNotExists?: boolean } = {},
): string {
  const sql = unwrapGuards(source);
  const spans = statementSpans(sql);

  const texts = spans.map(([from, to]) => {
    const masked = maskComments(sql.slice(from, to));
    const lead = /^\s*/.exec(masked)![0].length;

    return { lead, text: masked.slice(lead).replace(/;$/, "").trim() };
  });

  const created = createdTables(texts.map((entry) => entry.text));

  // A check added by name to a table the same file creates replaces the inline
  // check of that name (a column's `<table>_<column>_check` or the table's
  // `<table>_check`), so the `create table` holds the expression that wins and
  // the statement goes.
  const overrides = new Map<string, Map<string, string | null>>();
  const redundant = new Set<number>();

  for (const [index, { text }] of texts.entries()) {
    const check = ADD_CHECK.exec(text);

    if (check === null) {
      continue;
    }

    const table = qualified(check[1]!);
    const made = created.get(table);

    if (made === undefined) {
      continue;
    }

    const expression = check[3]!.replaceAll(/\s+/g, " ").trim();

    if (made.body.includes(`check (${expression})`)) {
      redundant.add(index);

      continue;
    }

    const name = unquoted(check[2]!);
    const base = table.slice(table.lastIndexOf(".") + 1);

    const inline = texts[made.index]!.text;
    const named = `constraint:${name}`;

    const key = hasInlineCheck(inline, made, named)
      ? named
      : name === `${base}_check`
        ? ""
        : [...made.columns].find(
            (column) => name === `${base}_${column}_check`,
          );

    if (
      key === undefined ||
      !hasInlineCheck(texts[made.index]!.text, made, key)
    ) {
      continue;
    }

    const held = overrides.get(table) ?? new Map<string, string | null>();

    if (readsOnly(check[3]!, made.columns)) {
      held.set(key, check[3]!.trim());
      redundant.add(index);
    } else {
      held.set(key, null);
    }

    overrides.set(table, held);
  }

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

      const head = CREATE_TABLE_BODY.exec(text);

      const made = head === null ? undefined : created.get(qualified(head[1]!));

      const held =
        head === null ? undefined : overrides.get(qualified(head[1]!));

      const replaced =
        made !== undefined && held !== undefined && made.index === index
          ? withInlineChecks(original, text, made, lead, held)
              .slice(lead)
              .replace(/;$/, "")
          : body;

      const table = CREATE_TABLE.exec(text);

      if (
        table !== null &&
        options.keepIfNotExists !== true &&
        !appTables.has(qualified(table[2]!))
      ) {
        return `${prefix}${replaced.replace(/^(create\s+(?:unlogged\s+)?table\s+)if\s+not\s+exists\s+/i, "$1")}${semicolon}`;
      }

      if (replaced !== body) {
        return `${prefix}${replaced.replace(/;$/, "")}${semicolon}`;
      }

      const indexed = CREATE_INDEX.exec(text);

      if (
        indexed !== null &&
        options.keepIfNotExists !== true &&
        !appTables.has(qualified(indexed[3]!))
      ) {
        return `${prefix}${body.replace(/^(create\s+(?:unique\s+)?index\s+)(?:concurrently\s+)?if\s+not\s+exists\s+/i, "$1")}${semicolon}`;
      }

      if (redundant.has(index)) {
        return prefix.trim() === "" ? "" : prefix.replace(/\s+$/, "\n");
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
  String.raw`^create\s+(?:constraint\s+)?trigger\s+(${NAME})(?![\w$])[\s\S]*?\bon\s+(${TABLE_NAME})`,
  "i",
);

const ADD_CONSTRAINT = new RegExp(
  String.raw`^alter\s+table\s+(?:only\s+)?(${TABLE_NAME})\s+add\s+constraint\s+(${NAME})(?![\w$])`,
  "i",
);

const DROP_FUNCTION = /^drop\s+function\s+if\s+exists\s/i;

/**
 * `sql` that runs again: a `drop` before each policy, trigger and constraint
 * the file creates and `if not exists` on each column it adds. The migrations
 * workflow writes every module into each migration, so each statement a
 * migration repeats must be safe to repeat.
 */
export function rerunnableDdl(source: string): string {
  // A policy on a Supabase-owned table sits in a `do` block a rerun can't drop
  // it before, so the block is unwrapped first.
  const sql = unwrapGuards(source, { types: false });

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

      if (DROP_FUNCTION.test(text)) {
        // A module that is off in this render drops its functions, but a
        // policy an earlier render created can still call one. The rerun
        // keeps such a function.
        const statement = rest.trimEnd().replace(/;$/, "");

        return `${head}do $$ begin ${statement}; exception when dependent_objects_still_exist then null; end $$;\n`;
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
