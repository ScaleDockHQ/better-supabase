import type { SelectOp } from "../ir/types.ts";
import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { DbError } from "./errors.ts";
import type { Executor } from "./executor.ts";
import type { Result } from "./result.ts";
import type { OperationRunner } from "./runner.ts";

import { dbError } from "./errors.ts";
import { AsyncResult, err, ok } from "./result.ts";
import { vectorLiteral, type SearchInput } from "./search.ts";

/**
 * `db.$search({ score: true })`: the ranked ids and scores from
 * `search_<table>_scores`, then those rows through the table (RLS and
 * `where` apply), best first, each with `$score`.
 */
async function scoredSearch(
  runner: OperationRunner,
  table: TableMeta,
  fnArgs: Readonly<Record<string, unknown>>,
  args: SearchInput,
  hint: (error: DbError) => DbError,
): Promise<Result<readonly unknown[]>> {
  const [key, ...rest] = table.primaryKey;
  if (key === undefined || rest.length > 0) {
    return err(
      dbError(
        "invalid_request",
        "db.$search({ score: true }) needs a table with a one-column primary key",
        { table: table.key },
      ),
    );
  }
  const { builder } = runner.runtime;
  // The scores function's rows, read like a table so PostgREST and SQL
  // executors both run it; RLS applies inside the function.
  const scoresTable: TableMeta = {
    key: `${table.key}$scores`,
    name: `search_${table.name}_scores`,
    schema: table.schema,
    kind: "view",
    columns: {
      id: { db: "id", type: "jsonb", nullable: false, hasDefault: false },
      score: {
        db: "score",
        type: "float8",
        nullable: false,
        hasDefault: false,
      },
    },
    primaryKey: [],
    uniqueKeys: {},
    relations: {},
    flags: {},
  };
  const scored = await runner.runInternal(
    {
      kind: "select",
      table: scoresTable,
      selection: builder.selection(scoresTable, ["id", "score"], undefined),
      where: undefined,
      orderBy: [],
      limit: undefined,
      offset: undefined,
      count: undefined,
      head: false,
      single: undefined,
      source: {
        schema: table.schema,
        name: scoresTable.name,
        args: fnArgs,
      },
    },
    table,
    args.signal,
  );
  if (!scored.ok) {
    return err(hint(scored.error));
  }
  const ranked = scored.data.rows.flatMap((row) =>
    row["score"] === undefined || row["score"] === null
      ? []
      : [{ id: row["id"], score: Number(row["score"]) }],
  );
  if (ranked.length === 0) {
    return ok([]);
  }
  const byId = new Map(ranked.map((entry) => [String(entry.id), entry]));
  const op: SelectOp = {
    kind: "select",
    table,
    selection: builder.selection(table, args.select, args.include),
    where: builder.where(table, {
      AND: [
        ...(args.where === undefined ? [] : [args.where]),
        { [key]: { in: ranked.map((entry) => entry.id) } },
      ],
    }),
    orderBy: [],
    limit: ranked.length,
    offset: undefined,
    count: undefined,
    head: false,
    single: undefined,
  };
  const result = await runner.run(op, {}, args.signal);
  if (!result.ok) {
    return result;
  }
  return ok(
    result.data.rows
      .flatMap((row) => {
        const entry = byId.get(String(row[key]));
        return entry ? [{ ...row, $score: entry.score }] : [];
      })
      .toSorted((a, b) => b.$score - a.$score),
  );
}

/** `db.$search(table, args)`: nearest rows from the table's `search_<table>` function. */
export function searchTable(
  runner: OperationRunner,
  base: Executor,
  meta: SchemaMeta,
  name: string,
  args: SearchInput,
): AsyncResult<readonly unknown[]> {
  return AsyncResult.from(async (): Promise<Result<readonly unknown[]>> => {
    const table = Object.hasOwn(meta.tables, name)
      ? meta.tables[name]
      : undefined;
    if (!table) {
      return err(
        dbError("invalid_request", `db.$search(): unknown table "${name}"`),
      );
    }
    if (!base.functionSources) {
      return err(
        dbError(
          "invalid_request",
          `db.$search() reads from a function; the ${base.name} executor doesn't support that`,
          { table: table.key },
        ),
      );
    }
    const textOnly =
      (args.vector === undefined || args.vector === null) &&
      args.text !== undefined;
    const query = textOnly ? null : vectorLiteral(args.vector ?? []);
    const k = args.k ?? 10;
    if (query === undefined || !Number.isInteger(k) || k < 1) {
      return err(
        dbError(
          "invalid_input",
          "db.$search() needs a vector of finite numbers (or text alone on a hybrid entry) and a positive integer k",
          { table: table.key },
        ),
      );
    }
    const { builder } = runner.runtime;
    const fnArgs = {
      query,
      k,
      ...(args.filter === undefined ? {} : { filter: args.filter }),
      ...(args.text === undefined ? {} : { text_query: args.text }),
    };
    const hint = (error: DbError): DbError =>
      error.code === "PGRST202" || error.code === "42883"
        ? {
            ...error,
            hint: `Add "${table.schema}.${table.name}" to vectorSearch in better-supabase.config.ts (with prefilter or hybrid for filter and text) and run \`better-supabase sql sync\`.`,
          }
        : error;
    if (args.score) {
      return scoredSearch(runner, table, fnArgs, args, hint);
    }
    const op: SelectOp = {
      kind: "select",
      table,
      selection: builder.selection(table, args.select, args.include),
      where: builder.where(table, args.where),
      orderBy: [],
      limit: k,
      offset: undefined,
      count: undefined,
      head: false,
      single: undefined,
      source: {
        schema: table.schema,
        name: `search_${table.name}`,
        args: fnArgs,
      },
    };
    const result = await runner.run(op, {}, args.signal);
    if (result.ok) {
      return ok(result.data.rows);
    }
    return err(hint(result.error));
  });
}
