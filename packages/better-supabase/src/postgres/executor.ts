import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
  RpcContext,
} from "../core/executor.ts";
import type { Result } from "../core/result.ts";
import type { Operation } from "../ir/types.ts";

import { compileSql, quoteIdent, type SqlPlan } from "../compile/sql.ts";
import { isPlainObject } from "../core/clone.ts";
import {
  dbError,
  mapDbError,
  type RawDbError,
  withMaxAffected,
} from "../core/errors.ts";
import { err, ok, toDbError } from "../core/result.ts";

/**
 * Anything that runs parameterized SQL: `ctx.postgres` from
 * `@supabase/server/middleware/postgres`, or a client from `createPostgres()`.
 */
export interface SqlClient {
  queryRaw<T = Record<string, unknown>>(
    text: string,
    params?: unknown[],
  ): Promise<T[]>;
  /**
   * Runs `fn` on one connection in one transaction. Optional; without it
   * `db.$many` sends its statements separately.
   */
  transaction?<T>(fn: (client: SqlClient) => Promise<T>): Promise<T>;
}

interface PgErrorLike {
  readonly code?: string;
  readonly message?: string;
  readonly detail?: string;
  readonly hint?: string;
  readonly constraint?: string;
  readonly column?: string;
  readonly table?: string;
  /** `@supabase/server`'s `PostgresPoolError` puts `retryAfterMs` here. */
  readonly details?: unknown;
}

function isPgError(value: unknown): value is PgErrorLike {
  // SAFETY: value is a non-null object here, and the code field is checked before use.
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as PgErrorLike).code === "string"
  );
}

function retryAfterMsOf(details: unknown): number | undefined {
  if (
    typeof details !== "object" ||
    details === null ||
    !("retryAfterMs" in details)
  ) {
    return undefined;
  }

  const value = details.retryAfterMs;

  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

/** node-postgres error fields to the shape `mapDbError` reads. */
export function fromPgError(error: unknown): RawDbError | undefined {
  if (!isPgError(error)) {
    return undefined;
  }

  const raw: { -readonly [K in keyof RawDbError]: RawDbError[K] } = {};

  if (error.code !== undefined) {
    raw.code = error.code;
  }

  if (error.message !== undefined) {
    raw.message = error.message;
  }

  if (error.detail !== undefined) {
    raw.details = error.detail;
  }

  if (error.hint !== undefined) {
    raw.hint = error.hint;
  }

  if (error.constraint !== undefined) {
    raw.constraint = error.constraint;
  }

  if (error.column !== undefined) {
    raw.column = error.column;
  }

  if (error.table !== undefined) {
    raw.table = error.table;
  }

  const retryAfterMs = retryAfterMsOf(error.details);

  if (retryAfterMs !== undefined) {
    raw.retryAfterMs = retryAfterMs;
  }

  return raw;
}

async function run(
  client: SqlClient,
  plan: SqlPlan,
  op: Operation,
): Promise<ExecuteResult> {
  const rows = plan.rows
    ? (
        await client.queryRaw<{ row: Record<string, unknown> }>(
          plan.rows.text,
          [...plan.rows.params],
        )
      ).map((entry) => entry.row)
    : [];

  let count: number | null = null;

  if (plan.count) {
    const [first] = await client.queryRaw<{ count: number }>(plan.count.text, [
      ...plan.count.params,
    ]);

    count = first?.count ?? 0;
  } else if (op.kind !== "select") {
    count = rows.length;
  }

  for (const next of plan.chunks ?? []) {
    const more = await run(client, next, op);
    rows.push(...more.rows);
    count = (count ?? 0) + (more.count ?? 0);
  }

  return { rows, count };
}

/**
 * Executes repository operations as SQL on a direct Postgres connection.
 * Rows have the same shape as over PostgREST. RLS applies when the client
 * runs as the caller (`ctx.postgres`, `createPostgres().asUser()`).
 *
 * `maxAffected` fails the statement itself, so its writes roll back.
 * A call's `timeout` is checked before the statement starts; set
 * `statement_timeout` on the connection to bound a running statement.
 * `retry` does nothing here.
 */
export function postgresExecutor(client: SqlClient): Executor {
  const signatures: SignatureCache = new Map();

  return {
    name: "postgres",
    functionSources: true,
    execute: (op, context) => executeOn(client, op, context),
    rpc: (name, args, context) =>
      callFunction(client, name, args, context, signatures),
    async batch(ops, context) {
      if (!client.transaction) {
        return Promise.all(ops.map((op) => executeOn(client, op, context)));
      }

      try {
        return await client.transaction(async (scoped) => {
          const results: Result<ExecuteResult>[] = [];

          for (const op of ops) {
            const result = await executeOn(scoped, op, context);

            if (!result.ok) {
              throw new BatchFailed();
            }

            results.push(result);
          }

          return results;
        });
      } catch (cause) {
        if (!(cause instanceof BatchFailed)) {
          const raw = fromPgError(cause);

          if (!raw) {
            throw cause;
          }

          const error = mapDbError(raw, context.errorMappers);

          return ops.map(() => err(error));
        }

        // A failed statement aborts the transaction; run each on its own so
        // every operation still gets its own result.
        return Promise.all(ops.map((op) => executeOn(client, op, context)));
      }
    },
  };
}

class BatchFailed extends Error {}

async function executeOn(
  client: SqlClient,
  op: Operation,
  context: ExecuteContext,
): Promise<Result<ExecuteResult>> {
  let plan: SqlPlan;

  try {
    plan = compileSql(op);
  } catch (cause) {
    return err(toDbError(cause));
  }

  if (plan.never) {
    return ok({ rows: [], count: 0 });
  }

  if (context.signal?.aborted) {
    return err(dbError("aborted", "The request was aborted"));
  }

  // Rows and their count read one snapshot, and chunks commit together.
  const together =
    plan.chunks !== undefined ||
    (plan.rows !== undefined && plan.count !== undefined);

  let result: ExecuteResult;

  try {
    result =
      together && client.transaction
        ? await client.transaction((scoped) => run(scoped, plan, op))
        : await run(client, plan, op);
  } catch (cause) {
    const raw = fromPgError(cause);

    const error = raw
      ? mapDbError(raw, context.errorMappers)
      : toDbError(cause);

    return err(
      withMaxAffected(
        error,
        op.kind === "update" || op.kind === "delete"
          ? op.maxAffected
          : undefined,
      ),
    );
  }

  if (op.kind === "select" && op.single) {
    if (result.rows.length > 1) {
      return err(dbError("multiple_rows", `Expected one ${op.table.key} row`));
    }

    if (result.rows.length === 0 && op.single === "one") {
      return err(dbError("not_found", `No ${op.table.key} row matched`));
    }
  }

  return ok(result);
}

interface FunctionSignature {
  readonly returnsSet: boolean;
  readonly returnsVoid: boolean;
  readonly json: ReadonlySet<string>;
  /** OUT and TABLE parameters, which PostgREST drops from a call's arguments. */
  readonly outputOnly: ReadonlySet<string>;
}

/** Catalog lookups by `schema.name`, for calls without generated metadata. */
type SignatureCache = Map<string, FunctionSignature>;

const JSON_TYPES = new Set(["json", "jsonb"]);

const NO_NAMES: ReadonlySet<string> = new Set();

/** undefined_function, invalid_function_definition and datatype_mismatch: the function changed. */
const CHANGED_FUNCTION = new Set(["42883", "42P13", "42804"]);

async function signatureOf(
  client: SqlClient,
  name: string,
  context: RpcContext,
  cache: SignatureCache,
): Promise<FunctionSignature | undefined> {
  const fn = context.function;

  if (fn) {
    return {
      returnsSet: fn.returnsSet,
      returnsVoid: fn.returns === "void",
      json: new Set(
        fn.args
          .filter((arg) => JSON_TYPES.has(arg.type))
          .map((arg) => arg.name),
      ),
      outputOnly: NO_NAMES,
    };
  }

  const key = `${context.schema}.${name}`;
  const cached = cache.get(key);

  if (cached) {
    return cached;
  }

  const found = await lookUp(client, name, context.schema);

  if (found) {
    cache.set(key, found);
  }

  return found;
}

async function lookUp(
  client: SqlClient,
  name: string,
  schema: string,
): Promise<FunctionSignature | undefined> {
  const [found] = await client.queryRaw<{
    returns_set: boolean;
    returns_void: boolean;
    arg_names: (string | null)[] | null;
    arg_modes: string[] | null;
    arg_types: string[] | null;
  }>(
    "select p.proretset as returns_set, p.prorettype = 'pg_catalog.void'::pg_catalog.regtype as returns_void, p.proargnames as arg_names, p.proargmodes::text[] as arg_modes, (select array_agg(t.typname::text order by a.ordinality) from unnest(p.proargtypes::oid[]) with ordinality as a(oid, ordinality) join pg_catalog.pg_type t on t.oid = a.oid) as arg_types from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = $1 and p.proname = $2 limit 1",
    [schema, name],
  );

  if (!found) {
    return undefined;
  }

  const json = new Set<string>();
  const outputOnly = new Set<string>();

  if (found.arg_names && found.arg_types) {
    const modes = found.arg_modes;

    for (const [index, mode] of (modes ?? []).entries()) {
      const argName = found.arg_names[index];

      if ((mode === "o" || mode === "t") && argName) {
        outputOnly.add(argName);
      }
    }

    // Input parameters are modes i, v and b; no modes means all are inputs.
    const inputIndexes = modes
      ? modes.flatMap((mode, index) =>
          mode === "i" || mode === "v" || mode === "b" ? [index] : [],
        )
      : found.arg_names.map((_, index) => index);

    for (const [position, index] of inputIndexes.entries()) {
      const argName = found.arg_names[index];
      const type = found.arg_types[position];

      if (argName != null && type !== undefined && JSON_TYPES.has(type)) {
        json.add(argName);
      }
    }
  }

  return {
    returnsSet: found.returns_set,
    returnsVoid: found.returns_void,
    json,
    outputOnly,
  };
}

function argValue(value: unknown, json: boolean): unknown {
  if (value === null) {
    return null;
  }

  if (json) {
    return JSON.stringify(value);
  }

  if (typeof value === "bigint") {
    return value.toString();
  }

  if (Array.isArray(value)) {
    return value.map((item) => argValue(item, false));
  }

  if (isPlainObject(value)) {
    return JSON.stringify(value);
  }

  if (
    typeof value === "object" &&
    !(value instanceof Date) &&
    !(value instanceof Uint8Array)
  ) {
    return String(value);
  }

  return value;
}

async function callFunction(
  client: SqlClient,
  name: string,
  args: Readonly<Record<string, unknown>>,
  context: RpcContext,
  cache: SignatureCache,
): Promise<Result<unknown>> {
  if (context.signal?.aborted) {
    return err(dbError("aborted", "The request was aborted"));
  }

  try {
    const signature = await signatureOf(client, name, context, cache);

    if (!signature) {
      return err(
        mapDbError(
          {
            code: "PGRST202",
            message: `Could not find the function ${context.schema}.${name} in the database`,
          },
          context.errorMappers,
        ),
      );
    }

    const params: unknown[] = [];

    const named = Object.entries(args)
      .filter(
        ([key, value]) => value !== undefined && !signature.outputOnly.has(key),
      )
      .map(([key, value]) => {
        params.push(argValue(value, signature.json.has(key)));

        return `${quoteIdent(key)} => $${String(params.length)}`;
      });

    const call = `${quoteIdent(context.schema)}.${quoteIdent(name)}(${named.join(", ")})`;

    if (signature.returnsVoid) {
      await client.queryRaw(`select ${call}`, params);

      return ok(null);
    }

    const rows = await client.queryRaw<{ value: unknown }>(
      `select to_json(bs_call) as value from ${call} as bs_call`,
      params,
    );

    const values = rows.map((row) => row.value);

    return ok(signature.returnsSet ? values : (values[0] ?? null));
  } catch (cause) {
    const raw = fromPgError(cause);

    if (raw?.code && CHANGED_FUNCTION.has(raw.code)) {
      cache.delete(`${context.schema}.${name}`);
    }

    return err(raw ? mapDbError(raw, context.errorMappers) : toDbError(cause));
  }
}
