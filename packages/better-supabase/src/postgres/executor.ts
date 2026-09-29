import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
} from '../core/executor.ts';
import type { Result } from '../core/result.ts';
import type { Operation } from '../ir/types.ts';

import { compileSql, type SqlPlan } from '../compile/sql.ts';
import { dbError, mapDbError, type RawDbError } from '../core/errors.ts';
import { err, ok, toDbError } from '../core/result.ts';

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
}

function isPgError(value: unknown): value is PgErrorLike {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as PgErrorLike).code === 'string'
  );
}

/** node-postgres error fields to the shape `mapDbError` reads. */
export function fromPgError(error: unknown): RawDbError | undefined {
  if (!isPgError(error)) return undefined;
  const raw: { -readonly [K in keyof RawDbError]: RawDbError[K] } = {};
  if (error.code !== undefined) raw.code = error.code;
  if (error.message !== undefined) raw.message = error.message;
  if (error.detail !== undefined) raw.details = error.detail;
  if (error.hint !== undefined) raw.hint = error.hint;
  if (error.constraint !== undefined) raw.constraint = error.constraint;
  if (error.column !== undefined) raw.column = error.column;
  if (error.table !== undefined) raw.table = error.table;
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
  } else if (op.kind !== 'select') {
    count = rows.length;
  }
  return { rows, count };
}

/**
 * Executes repository operations as SQL on a direct Postgres connection.
 * Rows have the same shape as over PostgREST. RLS applies when the client
 * runs as the caller (`ctx.postgres`, `createPostgres().asUser()`).
 */
export function postgresExecutor(client: SqlClient): Executor {
  return {
    name: 'postgres',
    execute: (op, context) => executeOn(client, op, context),
    async batch(ops, context) {
      if (!client.transaction) {
        return Promise.all(ops.map((op) => executeOn(client, op, context)));
      }
      try {
        return await client.transaction(async (scoped) => {
          const results: Result<ExecuteResult>[] = [];
          for (const op of ops) {
            const result = await executeOn(scoped, op, context);
            if (!result.ok) throw new BatchFailed();
            results.push(result);
          }
          return results;
        });
      } catch (cause) {
        if (!(cause instanceof BatchFailed)) throw cause;
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
  if (plan.never) return ok({ rows: [], count: 0 });
  if (context.signal?.aborted)
    return err(dbError('aborted', 'The request was aborted'));
  let result: ExecuteResult;
  try {
    result = await run(client, plan, op);
  } catch (cause) {
    const raw = fromPgError(cause);
    return err(raw ? mapDbError(raw, context.errorMappers) : toDbError(cause));
  }
  if (op.kind === 'select' && op.single) {
    if (result.rows.length > 1)
      return err(dbError('multiple_rows', `Expected one ${op.table.key} row`));
    if (result.rows.length === 0 && op.single === 'one') {
      return err(dbError('not_found', `No ${op.table.key} row matched`));
    }
  }
  return ok(result);
}
