import type { ResolvedConfig } from "../../config/index.ts";
import type { ConsentRequest } from "../core/agent.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { PgQueryable } from "../db.ts";
import type { CliEnv } from "../env.ts";

import { sqlIdent } from "../../core/template.ts";
import { databaseUrl, stdinDatabaseUrl } from "../config.ts";
import { databaseHost, isLocalDatabaseUrl } from "../core/agent.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError, errorText } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { connect } from "../db.ts";
import { DB_URL_STDIN_ARG, STACK_ARG } from "./source-args.ts";

const DEFAULT_BATCH = 1000;

const ARGS = {
  column: {
    type: "positional",
    required: true,
    variadic: true,
    description:
      "The column to fill, as table.column or schema.table.column; `via <column>` after it names the foreign key --from follows",
  },
  from: {
    type: "string",
    description:
      "Copy the value from this column of the table the foreign key references (table.column or schema.table.column)",
    valueHint: "table.column",
  },
  via: {
    type: "string",
    description:
      "The foreign key column of the filled table that points at the --from table",
    valueHint: "column",
  },
  value: {
    type: "string",
    description:
      "Set this SQL literal instead: a quoted string with an optional cast, a number, true or false",
    valueHint: "literal",
  },
  "batch-size": {
    type: "string",
    description: "Rows to update per statement (default 1000)",
    valueHint: "n",
  },
  "dry-run": {
    type: "boolean",
    description: "Count the rows it would fill, and change nothing",
  },
} as const;

export type BackfillFlags = CliOptions<
  typeof ARGS & typeof DB_URL_STDIN_ARG & typeof STACK_ARG
> & { readonly _: readonly string[] };

/** A column as `schema`, `table` and `column`, unquoted. */
export interface ColumnPath {
  readonly schema: string;
  readonly table: string;
  readonly column: string;
}

const LITERAL =
  /^(?:'(?:[^']|'')*'(?:::[a-z_][\w.]*(?:\s*\(\s*\d+(?:\s*,\s*\d+)?\s*\))?(?:\[\])?)?|-?\d+(?:\.\d+)?|true|false)$/iu;

/** `table.column` or `schema.table.column`, in `public` without a schema. */
export function parseColumnPath(value: string, flag: string): ColumnPath {
  const parts = value.split(".");

  if (parts.length < 2 || parts.length > 3 || parts.some((part) => !part)) {
    throw new CliError(
      "invalid_value",
      `${flag} takes table.column or schema.table.column, got "${value}".`,
      { flag },
    );
  }

  const [schema, table, column] =
    parts.length === 3 ? parts : ["public", ...parts];

  return { schema: schema!, table: table!, column: column! };
}

const tableRef = (path: Pick<ColumnPath, "schema" | "table">): string =>
  `${sqlIdent(path.schema)}.${sqlIdent(path.table)}`;

const label = (path: ColumnPath): string =>
  `${path.schema}.${path.table}.${path.column}`;

/** Where the filled values come from. */
export type BackfillSource =
  | {
      readonly kind: "column";
      readonly from: ColumnPath;
      /** The foreign key column of the filled table. */
      readonly via: string;
      /** The column of the `from` table the foreign key references. */
      readonly key: string;
    }
  | { readonly kind: "value"; readonly value: string };

/**
 * The statements that fill `target`: `pending` counts the rows a batch can
 * fill, `stuck` the null rows it can't (no match through the foreign key), and
 * `batch` fills at most `size` of them and returns how many. Only rows where
 * the column is null are read or written, so the command can run again.
 */
export function backfillStatements(
  target: ColumnPath,
  source: BackfillSource,
  size: number,
): {
  readonly pending: string;
  readonly stuck: string;
  readonly batch: string;
} {
  const table = tableRef(target);
  const column = sqlIdent(target.column);

  switch (source.kind) {
    case "value": {
      return {
        pending: `select count(*)::bigint::text as count from ${table} where ${column} is null`,
        stuck: "select '0' as count",
        batch: `with batch as (
  select t.ctid as row_id from ${table} t
  where t.${column} is null
  limit ${String(size)}
  for update of t skip locked
), filled as (
  update ${table} t set ${column} = ${source.value}
  from batch where t.ctid = batch.row_id
  returning 1
)
select count(*)::int as filled from filled`,
      };
    }

    case "column": {
      const from = tableRef(source.from);
      const join = `join ${from} s on s.${sqlIdent(source.key)} = t.${sqlIdent(source.via)}`;
      const value = `s.${sqlIdent(source.from.column)}`;

      return {
        pending: `select count(*)::bigint::text as count from ${table} t ${join} where t.${column} is null and ${value} is not null`,
        stuck: `select count(*)::bigint::text as count from ${table} t where t.${column} is null and not exists (select 1 from ${from} s where s.${sqlIdent(source.key)} = t.${sqlIdent(source.via)} and ${value} is not null)`,
        batch: `with batch as (
  select t.ctid as row_id, ${value} as value from ${table} t
  ${join}
  where t.${column} is null and ${value} is not null
  limit ${String(size)}
  for update of t skip locked
), filled as (
  update ${table} t set ${column} = batch.value
  from batch where t.ctid = batch.row_id
  returning 1
)
select count(*)::int as filled from filled`,
      };
    }

    default: {
      const unreachable: never = source;

      return unreachable;
    }
  }
}

async function columnExists(
  client: PgQueryable,
  path: ColumnPath,
): Promise<boolean> {
  const { rows } = await client.query<{ found: boolean }>(
    `select exists (
  select 1 from pg_catalog.pg_attribute a
  join pg_catalog.pg_class c on c.oid = a.attrelid
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = $1 and c.relname = $2 and a.attname = $3
    and a.attnum > 0 and not a.attisdropped
) as found`,
    [path.schema, path.table, path.column],
  );

  return rows[0]?.found === true;
}

/**
 * The column of `from` that `via` on `target` references: the single-column
 * foreign key between the two, or else `from`'s single-column primary key.
 */
async function referencedKey(
  client: PgQueryable,
  target: ColumnPath,
  via: string,
  from: ColumnPath,
): Promise<string | undefined> {
  const { rows } = await client.query<{ key: string }>(
    `select r.attname as key from pg_catalog.pg_constraint c
join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
join pg_catalog.pg_attribute r on r.attrelid = c.confrelid and r.attnum = c.confkey[1]
where c.contype = 'f' and cardinality(c.conkey) = 1
  and c.conrelid = $1::regclass and c.confrelid = $2::regclass and a.attname = $3
union all
select a.attname from pg_catalog.pg_constraint c
join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
where c.contype = 'p' and cardinality(c.conkey) = 1 and c.conrelid = $2::regclass
limit 1`,
    [tableRef(target), tableRef(from), via],
  );

  return rows[0]?.key;
}

interface Parsed {
  readonly target: ColumnPath;
  readonly from?: ColumnPath;
  readonly via?: string;
  readonly value?: string;
  readonly size: number;
}

function parseArgs(args: BackfillFlags): Parsed {
  const [column, ...rest] = args._;

  if (column === undefined) {
    throw new CliError("usage", "Pass the column to fill, as table.column.", {
      flag: "column",
    });
  }

  let via = args.via;

  if (rest.length > 0) {
    if (rest.length !== 2 || rest[0] !== "via" || via !== undefined) {
      throw new CliError(
        "usage",
        `Unexpected ${rest.join(" ")}. Name the foreign key with \`via <column>\` or --via <column>, once.`,
      );
    }

    via = rest[1];
  }

  const target = parseColumnPath(column, "column");

  if ((args.from === undefined) === (args.value === undefined)) {
    throw new CliError(
      "usage",
      "Pass --from <table.column> with via <column>, or --value <literal>.",
      { flag: "--from" },
    );
  }

  const size =
    args["batch-size"] === undefined
      ? DEFAULT_BATCH
      : Number(args["batch-size"]);

  if (!Number.isInteger(size) || size < 1) {
    throw new CliError(
      "invalid_value",
      `--batch-size takes a whole number above 0, got "${args["batch-size"] ?? ""}".`,
      { flag: "--batch-size" },
    );
  }

  if (args.value !== undefined) {
    if (via !== undefined) {
      throw new CliError(
        "usage",
        "via names the key --from follows; --value needs none.",
        { flag: "--via" },
      );
    }

    if (!LITERAL.test(args.value.trim())) {
      throw new CliError(
        "invalid_value",
        `--value takes a SQL literal: a quoted string with an optional cast ('acme' or '1f0c...'::uuid), a number, true or false. Got ${args.value}.`,
        { flag: "--value" },
      );
    }

    return { target, value: args.value.trim(), size };
  }

  if (via === undefined) {
    throw new CliError(
      "usage",
      `--from needs the foreign key of ${target.table} to follow: via <column> or --via <column>.`,
      { flag: "--via" },
    );
  }

  return {
    target,
    from: parseColumnPath(args.from ?? "", "--from"),
    via,
    size,
  };
}

export interface BackfillDeps {
  readonly open: typeof connect;
  readonly log: (line: string) => void;
  readonly requireConsent: (request: ConsentRequest) => void;
}

const DEFAULT_DEPS: BackfillDeps = {
  open: connect,
  log: () => {},
  requireConsent: () => {},
};

const rowsText = (count: number): string =>
  `${String(count)} row${count === 1 ? "" : "s"}`;

/**
 * Fills the null values of a column in batches, from a column of the table a
 * foreign key references or from a literal. Each batch is its own statement, so
 * a long backfill never holds locks on more than one batch of rows.
 */
export async function runBackfill(
  config: ResolvedConfig,
  args: BackfillFlags,
  env: CliEnv,
  deps: Partial<BackfillDeps> = {},
  dbUrl?: string,
): Promise<CommandResult> {
  const { open, log, requireConsent } = { ...DEFAULT_DEPS, ...deps };
  const parsed = parseArgs(args);
  const { target } = parsed;
  const dryRun = args["dry-run"] === true;

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BSB_STACK,
  );

  if (!dryRun && !isLocalDatabaseUrl(url)) {
    requireConsent({
      effect: "database-write",
      detail: `db backfill fills ${label(target)} on ${databaseHost(url)}`,
    });
  }

  const { client, close } = await open(url);

  try {
    for (const path of [target, ...(parsed.from ? [parsed.from] : [])]) {
      if (!(await columnExists(client, path))) {
        throw new CliError(
          "not_found",
          `The database has no column ${label(path)}.`,
        );
      }
    }

    let source: BackfillSource;

    if (parsed.from !== undefined && parsed.via !== undefined) {
      if (!(await columnExists(client, { ...target, column: parsed.via }))) {
        throw new CliError(
          "not_found",
          `The database has no column ${target.schema}.${target.table}.${parsed.via} to follow.`,
        );
      }

      const key = await referencedKey(client, target, parsed.via, parsed.from);

      if (key === undefined) {
        throw new CliError(
          "invalid_input",
          `${target.table}.${parsed.via} has no foreign key to ${parsed.from.schema}.${parsed.from.table}, and that table has no single-column primary key to match it on.`,
        );
      }

      source = { kind: "column", from: parsed.from, via: parsed.via, key };
    } else {
      source = { kind: "value", value: parsed.value ?? "null" };
    }

    const statements = backfillStatements(target, source, parsed.size);

    const count = async (text: string): Promise<number> =>
      Number((await client.query<{ count: string }>(text)).rows[0]?.count ?? 0);

    const from =
      source.kind === "column"
        ? { from: label(source.from), via: source.via, key: source.key }
        : { value: source.value };

    if (dryRun) {
      const [pending, stuck] = [
        await count(statements.pending),
        await count(statements.stuck),
      ];

      return {
        code: 0,
        output: [
          `Would fill ${rowsText(pending)} of ${label(target)}.`,
          ...(stuck > 0
            ? [
                `${rowsText(stuck)} would stay null: their ${source.kind === "column" ? source.via : ""} is null or has no match with a value.`,
              ]
            : []),
        ].join("\n"),
        data: {
          column: label(target),
          ...from,
          dryRun: true,
          pending,
          remaining: stuck,
          filled: 0,
          batches: 0,
        },
      };
    }

    let filled = 0;
    let batches = 0;

    for (;;) {
      const { rows } = await client.query<{ filled: number }>(statements.batch);
      const done = rows[0]?.filled ?? 0;

      if (done === 0) {
        break;
      }

      filled += done;
      batches += 1;
      log(
        `Filled ${rowsText(filled)} of ${label(target)} (batch ${String(batches)}).`,
      );
    }

    const remaining = await count(
      `select count(*)::bigint::text as count from ${tableRef(target)} where ${sqlIdent(target.column)} is null`,
    );

    const lines = [
      filled === 0
        ? `${label(target)} has no null values to fill.`
        : `Filled ${rowsText(filled)} of ${label(target)} in ${String(batches)} batch${batches === 1 ? "" : "es"}.`,
    ];

    if (remaining > 0) {
      lines.push(
        source.kind === "column"
          ? `${rowsText(remaining)} are still null: their ${source.via} is null, has no match, or the match has no value (or another session held the row). Fill them, then run this again.`
          : `${rowsText(remaining)} are still null because another session held them. Run this again.`,
      );
    } else {
      lines.push(
        `No null values are left. \`better-supabase doctor --fix\` validates a not valid check on ${target.column}, and then the column can be set not null.`,
      );
    }

    return {
      code: 0,
      output: lines.join("\n"),
      data: {
        column: label(target),
        ...from,
        dryRun: false,
        filled,
        batches,
        remaining,
      },
    };
  } catch (cause) {
    if (cause instanceof CliError) {
      throw cause;
    }

    return {
      code: 1,
      errorCode: "failed",
      error: `db backfill ${label(target)} failed: ${errorText(cause)}`,
    };
  } finally {
    await close();
  }
}

export const dbBackfillCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db backfill"),
  args: { ...ARGS, ...DB_URL_STDIN_ARG, ...STACK_ARG },
  run: async (args, { config, env, io, log, requireConsent }) => {
    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    return runBackfill(
      config,
      args,
      env,
      { open: connect, log: log.info, requireConsent },
      dbUrl,
    );
  },
});
