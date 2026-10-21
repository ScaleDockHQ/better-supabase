import { readdir } from "node:fs/promises";
import { join } from "node:path";

import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { splitStatements, type SqlStatement } from "./shared.ts";

const NAME = String.raw`(?:"[^"]+"|[\w$]+)`;
const TABLE = String.raw`(${NAME}(?:\s*\.\s*${NAME})?)`;

const CREATE_TABLE = new RegExp(
  String.raw`^create\s+(?:(?:global\s+|local\s+)?(?:temporary|temp|unlogged)\s+)?table\s+(?:if\s+not\s+exists\s+)?${TABLE}`,
  "iu",
);

const ALTER_TABLE = new RegExp(
  String.raw`^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?${TABLE}`,
  "iu",
);

const CREATE_INDEX = new RegExp(
  String.raw`^create\s+(?:unique\s+)?index\s+(concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:${NAME}\s+)?on\s+(?:only\s+)?${TABLE}`,
  "iu",
);

const ADD_CONSTRAINT =
  /\badd\s+(?:constraint\s+(?:"[^"]+"|[\w$]+)\s+)?(foreign\s+key|check)\b/iu;

const NOT_VALID = /\bnot\s+valid\b/iu;

const ALTER_TYPE =
  /\balter\s+(?:column\s+)?(?:"[^"]+"|[\w$]+)\s+(?:set\s+data\s+)?type\b/iu;

const SET_NOT_NULL = /\bset\s+not\s+null\b/iu;
const VALIDATE = /\bvalidate\s+constraint\b/iu;

const ADD_COLUMN_DEFAULT =
  /\badd\s+(?:column\s+)?(?:if\s+not\s+exists\s+)?(?:"[^"]+"|[\w$]+)\s[^,]*?\bdefault\s+([^,]+)/giu;

const VOLATILE =
  /\b(?:gen_random_uuid|uuid_generate_v[14]|clock_timestamp|timeofday|random|nextval|statement_timestamp)\s*\(/iu;

const LOCK_TIMEOUT = /^set\s+(?:local\s+)?lock_timeout\b/iu;

const EXCLUSIVE =
  /^(?:drop\s+table|truncate|vacuum\s+full|reindex\b(?!.*\bconcurrently\b)|lock\s+table|cluster\b)/iu;

const DROP =
  /^drop\s+table\b|\bdrop\s+(?:column\s+)?(?!constraint\b|default\b|not\b|identity\b|expression\b)(?:if\s+exists\s+)?(?:"[^"]+"|[\w$]+)/iu;

const RENAME =
  /\brename\s+(?!constraint\b)(?:column\s+)?(?:(?:"[^"]+"|[\w$]+)\s+)?to\b/iu;

/** `name` without quotes and with `public.` for an unqualified name, lower-cased. */
function tableKey(name: string): string {
  const parts = name
    .split(".")
    .map((part) => part.trim().replaceAll('"', "").toLowerCase());

  return parts.length === 1 ? `public.${parts[0] ?? ""}` : parts.join(".");
}

/** The version a migration file name or a `since` value starts with. */
export function migrationVersion(name: string): string {
  const base = name.slice(name.lastIndexOf("/") + 1);

  return base.replace(/\.sql$/u, "").split("_")[0] ?? base;
}

/**
 * The newest migration under `<root>/<supabaseDir>/migrations`, which `init`
 * and `adopt` write to `doctor.migrationSafety.since` so the migrations that
 * already ran aren't checked offline.
 */
export async function latestMigrationVersion(
  root: string,
  supabaseDir: string = "supabase",
): Promise<string | undefined> {
  const names = await readdir(join(root, supabaseDir, "migrations")).catch(
    () => [],
  );

  const versions = names
    .filter((name) => name.endsWith(".sql"))
    .map(migrationVersion)
    .toSorted();

  return versions.at(-1);
}

interface Statements {
  readonly file: TextFile;
  readonly statements: readonly SqlStatement[];
  /** The tables the file creates, which no one else reads yet. */
  readonly created: ReadonlySet<string>;
}

const statementsCache = new WeakMap<TextFile, Statements>();

function parse(file: TextFile): Statements {
  let parsed = statementsCache.get(file);

  if (parsed === undefined) {
    const statements = splitStatements(file.text);

    const created = new Set(
      statements.flatMap((statement) => {
        const match = CREATE_TABLE.exec(statement.text);

        return match?.[1] === undefined ? [] : [tableKey(match[1])];
      }),
    );

    parsed = { file, statements, created };
    statementsCache.set(file, parsed);
  }

  return parsed;
}

const pending = new WeakMap<DoctorContext, Promise<TextFile[]>>();

/**
 * The migrations to check: with a database, the ones it hasn't applied;
 * offline, the ones after `doctor.migrationSafety.since`, or the newest one
 * without it.
 */
export function unappliedMigrations(
  context: DoctorContext,
): Promise<TextFile[]> {
  let files = pending.get(context);

  if (files === undefined) {
    files = findUnapplied(context);
    pending.set(context, files);
  }

  return files;
}

async function findUnapplied(context: DoctorContext): Promise<TextFile[]> {
  const dir = `${context.configToml?.dir ?? "supabase"}/migrations/`;

  const migrations = (context.sqlFiles ?? [])
    .filter((file) => file.path.startsWith(dir))
    .toSorted((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));

  const db = context.database;

  if (db !== undefined && !("skipped" in db)) {
    try {
      const rows = await db.query<{ version: string }>(
        "select version from supabase_migrations.schema_migrations",
      );

      const applied = new Set(rows.map((row) => row.version));

      return migrations.filter(
        (file) => !applied.has(migrationVersion(file.path)),
      );
    } catch {
      // No migrations table: fall back to the offline scope.
    }
  }

  const since = context.config.doctor.migrationSafety?.since;

  if (since === undefined) {
    return migrations.slice(-1);
  }

  const after = migrationVersion(since);

  return migrations.filter((file) => migrationVersion(file.path) > after);
}

type Check = (
  parsed: Statements,
  statement: SqlStatement,
) => string | undefined;

/** A rule that runs `check` on each statement of the unapplied migrations. */
function perStatement(check: Check) {
  return async (context: DoctorContext): Promise<FindingInput[]> =>
    (await unappliedMigrations(context)).flatMap((file) => {
      const parsed = parse(file);

      return parsed.statements.flatMap((statement) => {
        const message = check(parsed, statement);

        return message === undefined
          ? []
          : [
              {
                message: `${file.path}:${String(statement.line)}: ${message}`,
                target: `${file.path}:${String(statement.line)}`,
                location: { file: file.path, line: statement.line },
              },
            ];
      });
    });
}

/** The table an `alter table` statement changes, unless the same file created it. */
function alteredTable(
  parsed: Statements,
  statement: SqlStatement,
): string | undefined {
  const match = ALTER_TABLE.exec(statement.text);
  const table = match?.[1] === undefined ? undefined : tableKey(match[1]);

  return table === undefined || parsed.created.has(table) ? undefined : table;
}

const indexWithoutConcurrently: Check = (parsed, statement) => {
  const match = CREATE_INDEX.exec(statement.text);

  if (match === null || match[1] !== undefined || match[2] === undefined) {
    return;
  }

  const table = tableKey(match[2]);

  return parsed.created.has(table)
    ? undefined
    : `creates an index on ${table} without concurrently, which blocks writes to it until the index is built.`;
};

const constraintWithoutNotValid: Check = (parsed, statement) => {
  const table = alteredTable(parsed, statement);
  const kind = ADD_CONSTRAINT.exec(statement.text)?.[1];

  if (
    table === undefined ||
    kind === undefined ||
    NOT_VALID.test(statement.text)
  ) {
    return;
  }

  return `adds a ${kind.toLowerCase().replace(/\s+/u, " ")} to ${table} without not valid, which scans every row while it holds a lock.`;
};

const rewriteOrScan: Check = (parsed, statement) => {
  const table = alteredTable(parsed, statement);

  if (table === undefined) {
    return;
  }

  if (ALTER_TYPE.test(statement.text)) {
    return `changes a column type of ${table}, which can rewrite the table under an access exclusive lock.`;
  }

  const validated = parsed.statements.some(
    (each) =>
      each.line < statement.line &&
      VALIDATE.test(each.text) &&
      alteredTable(parsed, each) === table,
  );

  return SET_NOT_NULL.test(statement.text) && !validated
    ? `sets not null on a column of ${table}, which scans every row under an access exclusive lock.`
    : undefined;
};

const volatileDefault: Check = (parsed, statement) => {
  const table = alteredTable(parsed, statement);

  if (table === undefined) {
    return;
  }

  for (const match of statement.text.matchAll(ADD_COLUMN_DEFAULT)) {
    if (VOLATILE.test(match[1] ?? "")) {
      return `adds a column to ${table} with a volatile default (${(match[1] ?? "").trim()}), which rewrites every row.`;
    }
  }

  return;
};

/** Whether `statement` takes an access exclusive lock on a table others use. */
function takesExclusiveLock(
  parsed: Statements,
  statement: SqlStatement,
): boolean {
  if (EXCLUSIVE.test(statement.text)) {
    return true;
  }

  const match = CREATE_INDEX.exec(statement.text);

  if (match?.[2] !== undefined && match[1] === undefined) {
    return !parsed.created.has(tableKey(match[2]));
  }

  return alteredTable(parsed, statement) !== undefined;
}

async function missingLockTimeout(
  context: DoctorContext,
): Promise<FindingInput[]> {
  return (await unappliedMigrations(context)).flatMap((file) => {
    const parsed = parse(file);

    const first = parsed.statements.find((statement) =>
      takesExclusiveLock(parsed, statement),
    );

    if (first === undefined) {
      return [];
    }

    const timeout = parsed.statements.some(
      (statement) =>
        statement.line <= first.line && LOCK_TIMEOUT.test(statement.text),
    );

    return timeout
      ? []
      : [
          {
            message: `${file.path} locks tables it didn't create (line ${String(first.line)}) without setting lock_timeout, so a long query ahead of it queues every read and write behind the migration.`,
            target: file.path,
            location: { file: file.path, line: first.line },
          },
        ];
  });
}

const dropOrRename: Check = (parsed, statement) => {
  const isDropTable = /^drop\s+table\b/iu.test(statement.text);
  const table = alteredTable(parsed, statement);

  if (isDropTable) {
    return "drops a table; app code that still reads it fails once this runs.";
  }

  if (table === undefined) {
    return;
  }

  if (RENAME.test(statement.text)) {
    return `renames ${table} or one of its columns; app code that uses the old name fails once this runs.`;
  }

  return DROP.test(statement.text)
    ? `drops a column of ${table}; app code that still reads it fails once this runs.`
    : undefined;
};

const LIBRARY_FUNCTION = String.raw`(?:"better_supabase"|better_supabase)\s*\.\s*("[^"]+"|[\w$]+)\s*\(`;

const DROP_FUNCTION = /^drop\s+(?:function|procedure)\s+(?:if\s+exists\s+)?/iu;

const CREATE_FUNCTION = new RegExp(
  String.raw`^create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+${LIBRARY_FUNCTION}`,
  "iu",
);

/** The text between the parenthesis at `open` and its match, or undefined. */
function parenthesized(text: string, open: number): string | undefined {
  let depth = 0;
  let quote: string | undefined;

  for (let index = open; index < text.length; index += 1) {
    const char = text.charAt(index);

    if (quote !== undefined) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        return text.slice(open + 1, index);
      }
    }
  }

  return undefined;
}

/**
 * How many input arguments a function argument list has: the top-level
 * commas, without `out` arguments, which are not part of the signature.
 */
function inputArity(args: string): number {
  const parts: string[] = [];
  let depth = 0;
  let quote: string | undefined;
  let start = 0;

  for (let index = 0; index < args.length; index += 1) {
    const char = args.charAt(index);

    if (quote !== undefined) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      parts.push(args.slice(start, index));
      start = index + 1;
    }
  }

  parts.push(args.slice(start));

  return parts.filter((part) => {
    const trimmed = part.trim();

    return trimmed !== "" && !/^out\s/iu.test(trimmed);
  }).length;
}

const functionName = (name: string): string =>
  name.replaceAll('"', "").toLowerCase();

/** Each `better_supabase` function a `drop function` statement names, with its arity. */
function droppedFunctions(
  text: string,
): readonly { readonly name: string; readonly arity: number }[] {
  const head = DROP_FUNCTION.exec(text);

  if (head === null) {
    return [];
  }

  const pattern = new RegExp(LIBRARY_FUNCTION, "giu");
  const dropped: { name: string; arity: number }[] = [];

  for (const match of text.slice(head[0].length).matchAll(pattern)) {
    const open = head[0].length + match.index + match[0].length - 1;
    const args = parenthesized(text, open);

    if (match[1] !== undefined && args !== undefined) {
      dropped.push({ name: functionName(match[1]), arity: inputArity(args) });
    }
  }

  return dropped;
}

const createdSignatures = new WeakMap<Statements, ReadonlySet<string>>();

/** `name/arity` for every `better_supabase` function the file creates. */
function createdFunctions(parsed: Statements): ReadonlySet<string> {
  let created = createdSignatures.get(parsed);

  if (created === undefined) {
    created = new Set(
      parsed.statements.flatMap((statement) => {
        const match = CREATE_FUNCTION.exec(statement.text);

        if (match?.[1] === undefined) {
          return [];
        }

        const args = parenthesized(statement.text, match[0].length - 1);

        return args === undefined
          ? []
          : [`${functionName(match[1])}/${String(inputArity(args))}`];
      }),
    );
    createdSignatures.set(parsed, created);
  }

  return created;
}

const droppedLibraryFunction: Check = (parsed, statement) => {
  const created = createdFunctions(parsed);

  const changed = droppedFunctions(statement.text).filter(
    (each) => !created.has(`${each.name}/${String(each.arity)}`),
  );

  if (changed.length === 0) {
    return;
  }

  const names = changed
    .map((each) => `better_supabase.${each.name}`)
    .join(", ");

  return `drops ${names} without creating it again with the same arguments. A call with positional arguments, or a grant on the old signature, fails once this runs.`;
};

const EXPAND =
  "Expand and contract: add the new shape, deploy app code that uses it, then remove the old one in a later migration.";

export const MIGRATION_SAFETY_RULES: readonly Rule[] = [
  {
    code: "BS229",
    severity: "warning",
    title: "Index created without concurrently",
    description:
      "A migration creates an index on an existing table without `concurrently`. The build holds a lock that blocks inserts, updates and deletes on the table until it finishes. Use `create index concurrently`, in a migration file of its own: the statement can't run inside a transaction block.",
    check: perStatement(indexWithoutConcurrently),
  },
  {
    code: "BS230",
    severity: "warning",
    title: "Constraint added without not valid",
    description:
      "A migration adds a foreign key or check to an existing table without `not valid`, so Postgres checks every row while it holds the lock. Add it with `not valid`, then run `alter table ... validate constraint` in a later statement, which takes a lighter lock.",
    check: perStatement(constraintWithoutNotValid),
  },
  {
    code: "BS231",
    severity: "warning",
    title: "Column type change or set not null",
    description:
      "A migration changes a column type or sets `not null` on an existing table. A type change can rewrite the table, and `set not null` scans every row, both under an access exclusive lock. For `not null`, add `check (column is not null) not valid`, validate it, then set not null. For a type, add a new column and backfill it.",
    check: perStatement(rewriteOrScan),
  },
  {
    code: "BS232",
    severity: "warning",
    title: "Column added with a volatile default",
    description:
      "A migration adds a column with a volatile default, such as `gen_random_uuid()` or `clock_timestamp()`, to an existing table. Postgres writes the value into every row under an access exclusive lock. Add the column without a default, backfill it in batches, then set the default.",
    check: perStatement(volatileDefault),
  },
  {
    code: "BS233",
    severity: "warning",
    title: "Migration without lock_timeout",
    description:
      "A migration takes an access exclusive lock on an existing table without `set lock_timeout`. While it waits behind a long query, every read and write of the table queues behind it. Start the file with `set lock_timeout = '5s';` and retry the migration when it times out.",
    check: missingLockTimeout,
  },
  {
    code: "BS234",
    severity: "info",
    title: "Migration drops or renames",
    description: `A migration drops or renames a table or column. App code deployed before it still uses the old name and fails once it runs. ${EXPAND}`,
    check: perStatement(dropOrRename),
  },
  {
    code: "BS235",
    severity: "warning",
    title: "Migration drops a better-supabase function",
    description:
      "A migration drops a `better_supabase` function and doesn't create it again with the same number of arguments. A schema diff does this when a better-supabase release changes a function's signature, such as `audit()` in 0.12. Calls with positional arguments and grants on the old signature fail once it runs. Read the upgrade notes for the release (/docs/migration), then update your calls and grants in the same migration.",
    check: perStatement(droppedLibraryFunction),
  },
];
