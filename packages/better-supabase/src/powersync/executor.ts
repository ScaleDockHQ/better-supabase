import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
} from "../core/executor.ts";
import type { InsertOp, Operation } from "../ir/types.ts";
import type { TableMeta } from "../schema/types.ts";

import {
  compileSqlite,
  keyPages,
  type SqliteColumn,
  type SqliteCompilerOptions,
  type SqliteInsertPlan,
  type SqliteKeyedPlan,
  type SqliteKeys,
  type SqlitePlan,
  type SqliteQuery,
  type SqliteValue,
} from "../compile/sqlite.ts";
import {
  type DbError,
  dbError,
  mapDbError,
  type ErrorMapper,
  type RawDbError,
} from "../core/errors.ts";
import { err, ok, type Result, toDbError } from "../core/result.ts";

/** What a PowerSync database, transaction or lock context can run. */
export interface SqliteContextLike {
  getAll<T>(sql: string, parameters?: unknown[]): Promise<T[]>;
  execute(sql: string, parameters?: unknown[]): Promise<unknown>;
}

/**
 * The part of `PowerSyncDatabase` (`@powersync/react-native`,
 * `@powersync/web`, `@powersync/node`) the executor uses. Typed by shape,
 * so better-supabase doesn't depend on PowerSync.
 */
export interface PowerSyncDatabaseLike extends SqliteContextLike {
  writeTransaction<T>(
    callback: (tx: SqliteContextLike) => Promise<T>,
  ): Promise<T>;
  onChange?(
    handler: {
      onChange: (event: { changedTables: string[] }) => Promise<void> | void;
    },
    options?: {
      tables?: string[];
      throttleMs?: number;
      signal?: AbortSignal;
    },
  ): () => void;
}

export interface PowerSyncExecutorOptions extends SqliteCompilerOptions {
  /**
   * A primary key for an insert that leaves it out. PowerSync tables key on
   * a text `id` that the client creates. Defaults to
   * `crypto.randomUUID()`, else SQLite's `uuid()` (PowerSync registers it).
   */
  readonly newId?: (table: TableMeta) => string | Promise<string>;
}

const UNIQUE = /(?:UNIQUE|PRIMARY KEY) constraint failed: (.+)$/m;
const NOT_NULL = /NOT NULL constraint failed: (?:[^.\s]+\.)?(\S+)/;
const CHECK = /CHECK constraint failed: ?(\S+)?/;

const unqualified = (column: string): string =>
  column.trim().replace(/^[^.]+\./, "");

/**
 * A SQLite constraint error in the shape `mapDbError` reads from Postgres:
 * its SQLSTATE, and the columns in Postgres's `Key (...)` detail format.
 */
export function fromSqliteError(cause: unknown): RawDbError | undefined {
  if (!(cause instanceof Error)) return undefined;
  const message = cause.message;
  const unique = UNIQUE.exec(message);
  if (unique?.[1]) {
    const columns = unique[1].split(",").map(unqualified);
    return {
      code: "23505",
      message,
      details: `Key (${columns.join(", ")})=(...) already exists.`,
    };
  }
  if (message.includes("FOREIGN KEY constraint failed"))
    return { code: "23503", message };
  const notNull = NOT_NULL.exec(message);
  if (notNull?.[1]) return { code: "23502", message, column: notNull[1] };
  const check = CHECK.exec(message);
  if (check)
    return {
      code: "23514",
      message,
      ...(check[1] ? { constraint: check[1] } : {}),
    };
  return undefined;
}

const TIMESTAMP =
  /^(\d{4,}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|z|[+-]\d{2}(?::?\d{2})?)?$/;

/**
 * Timestamp text as PostgREST sends it (`2026-01-02T10:00:00.5+00:00`), from
 * whatever the sync wrote (`2026-01-02 10:00:00.500000Z`).
 */
export function postgrestTimestamp(value: string): string {
  const match = TIMESTAMP.exec(value);
  if (!match) return value;
  const [, date, time, fraction, zone] = match;
  const trimmed = fraction?.replace(/0+$/, "");
  let offset = "+00:00";
  if (zone && zone !== "Z" && zone !== "z") {
    const digits = zone.replace(":", "");
    offset = `${digits.slice(0, 3)}:${digits.slice(3, 5) || "00"}`;
  }
  return `${date}T${time}${trimmed ? `.${trimmed}` : ""}${offset}`;
}

function decodeValue(column: SqliteColumn, value: unknown): unknown {
  if (value === null || value === undefined) return null;
  switch (column.decode) {
    case "boolean":
      return value === 1 || value === true || value === "1" || value === "true";
    case "json":
      if (typeof value !== "string") return value;
      try {
        const parsed: unknown = JSON.parse(value);
        return parsed;
      } catch {
        return value;
      }
    case "timestamptz":
      return typeof value === "string" ? postgrestTimestamp(value) : value;
    case "raw":
      return typeof value === "bigint" ? Number(value) : value;
    default: {
      const exhaustive: never = column.decode;
      return exhaustive;
    }
  }
}

function decode(
  rows: readonly Record<string, unknown>[],
  columns: readonly SqliteColumn[],
): Record<string, unknown>[] {
  return rows.map((row) => {
    const out: Record<string, unknown> = {};
    for (const column of columns)
      out[column.alias] = decodeValue(column, row[column.alias]);
    return out;
  });
}

async function all(
  context: SqliteContextLike,
  query: SqliteQuery,
): Promise<Record<string, unknown>[]> {
  return context.getAll<Record<string, unknown>>(query.text, [...query.params]);
}

function keyValue(value: unknown): SqliteValue {
  if (value === null || value === undefined) return null;
  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "bigint"
  )
    return value;
  return String(value);
}

async function keysOf(
  context: SqliteContextLike,
  query: SqliteQuery,
): Promise<SqliteKeys> {
  const rows = await all(context, query);
  return rows.map((row) => Object.values(row).map(keyValue));
}

async function readBack(
  context: SqliteContextLike,
  plan: SqliteInsertPlan | SqliteKeyedPlan,
  keys: SqliteKeys,
): Promise<Record<string, unknown>[]> {
  if (!plan.returning) return [];
  const rows: Record<string, unknown>[] = [];
  for (const page of keyPages(keys))
    rows.push(...(await all(context, plan.returning.read(page))));
  return decode(rows, plan.returning.columns);
}

async function runInsert(
  tx: SqliteContextLike,
  plan: SqliteInsertPlan,
): Promise<ExecuteResult> {
  const written: (readonly SqliteValue[])[] = [];
  for (const row of plan.rows) {
    const [found] = row.existing ? await all(tx, row.existing) : [];
    if (found) {
      const { _tenant: tenant, ...key } = found;
      const otherTenant = row.tenant !== undefined && tenant !== row.tenant;
      if (plan.conflict === "ignore" || otherTenant || !row.update) continue;
      const existingKey = Object.values(key).map(keyValue);
      const statement = row.update(existingKey);
      await tx.execute(statement.text, [...statement.params]);
      written.push(existingKey);
      continue;
    }
    await tx.execute(row.insert.text, [...row.insert.params]);
    written.push(row.key);
  }
  const rows = await readBack(tx, plan, written);
  return { rows, count: written.length };
}

/** Thrown inside the write transaction so it rolls back; mapped to `max_affected`. */
class MaxAffected extends Error {
  readonly error: DbError;

  constructor(affected: number, maxAffected: number) {
    const message = `The write affects ${affected} rows, more than maxAffected (${maxAffected}) allows`;
    super(message);
    this.error = dbError("max_affected", message, { maxAffected });
  }
}

async function runKeyed(
  tx: SqliteContextLike,
  plan: SqliteKeyedPlan,
): Promise<ExecuteResult> {
  const keys = await keysOf(tx, plan.keys);
  if (keys.length === 0) return { rows: [], count: 0 };
  if (plan.maxAffected !== undefined && keys.length > plan.maxAffected)
    throw new MaxAffected(keys.length, plan.maxAffected);
  const before =
    plan.kind === "delete" ? await readBack(tx, plan, keys) : undefined;
  for (const page of keyPages(keys)) {
    const statement = plan.apply(page);
    await tx.execute(statement.text, [...statement.params]);
  }
  const rows = before ?? (await readBack(tx, plan, keys));
  return { rows, count: keys.length };
}

async function run(
  db: PowerSyncDatabaseLike,
  plan: Exclude<SqlitePlan, { kind: "never" }>,
): Promise<ExecuteResult> {
  switch (plan.kind) {
    case "select": {
      const rows = plan.rows
        ? decode(await all(db, plan.rows), plan.columns)
        : [];
      let count: number | null = null;
      if (plan.count) {
        const [first] = await all(db, plan.count);
        count = Number(first?.["count"] ?? 0);
      }
      return { rows, count };
    }
    case "insert":
      return db.writeTransaction((tx) => runInsert(tx, plan));
    case "update":
    case "delete":
      return db.writeTransaction((tx) => runKeyed(tx, plan));
    default: {
      const exhaustive: never = plan;
      return exhaustive;
    }
  }
}

/** Hermes has no `crypto` unless the app installs a polyfill. */
function randomId(): string | undefined {
  // SAFETY: lib.dom types `crypto` as always present; Hermes may lack it.
  const { crypto } = globalThis as {
    readonly crypto?: { readonly randomUUID?: () => string };
  };
  return crypto?.randomUUID?.();
}

/** Inserts with a missing single-column key get one, as PowerSync needs. */
async function withIds(
  db: SqliteContextLike,
  op: InsertOp,
  newId: ((table: TableMeta) => string | Promise<string>) | undefined,
): Promise<InsertOp> {
  const [key, ...rest] = op.table.primaryKey;
  if (key === undefined || rest.length > 0) return op;
  const column = op.table.columns[key];
  if (!column || (column.type !== "uuid" && column.type !== "text")) return op;
  if (op.rows.every((row) => row[column.db] !== undefined)) return op;
  const next = async (): Promise<string> => {
    if (newId) return newId(op.table);
    const random = randomId();
    if (random !== undefined) return random;
    const [row] = await db.getAll<{ id: string }>("select uuid() as id");
    if (!row) throw new TypeError("select uuid() returned no row");
    return row.id;
  };
  const rows: Record<string, unknown>[] = [];
  for (const row of op.rows)
    rows.push(
      row[column.db] === undefined
        ? { ...row, [column.db]: await next() }
        : row,
    );
  return { ...op, rows };
}

async function executeOn(
  db: PowerSyncDatabaseLike,
  op: Operation,
  context: ExecuteContext,
  options: PowerSyncExecutorOptions,
): Promise<Result<ExecuteResult>> {
  if (context.signal?.aborted)
    return err(dbError("aborted", "The request was aborted"));
  let plan: SqlitePlan;
  try {
    const prepared =
      op.kind === "insert" ? await withIds(db, op, options.newId) : op;
    plan = compileSqlite(prepared, options);
  } catch (cause) {
    return err(toDbError(cause));
  }
  if (plan.kind === "never") return ok({ rows: [], count: 0 });
  let result: ExecuteResult;
  try {
    result = await run(db, plan);
  } catch (cause) {
    return err(mapped(cause, context.errorMappers));
  }
  if (op.kind === "select" && op.single) {
    if (result.rows.length > 1)
      return err(dbError("multiple_rows", `Expected one ${op.table.key} row`));
    if (result.rows.length === 0 && op.single === "one")
      return err(dbError("not_found", `No ${op.table.key} row matched`));
  }
  return ok(result);
}

function mapped(cause: unknown, mappers: readonly ErrorMapper[]): DbError {
  if (cause instanceof MaxAffected) return cause.error;
  const raw = fromSqliteError(cause);
  return raw ? mapDbError(raw, mappers) : toDbError(cause);
}

/**
 * Runs repository operations on PowerSync's local SQLite database, so the
 * same repositories and list definitions work offline on native. Reads
 * return rows in the PostgREST shape (booleans, parsed JSON, ISO
 * timestamps); writes go through PowerSync's upload queue. What SQLite
 * can't express (includes, full-text search, function sources) returns a
 * `DbError` of kind `unsupported` without running anything.
 * `maxAffected` is checked against the selected keys before any write; a
 * call's `timeout` is checked before the statement starts, and `retry`
 * does nothing here.
 *
 * ```ts
 * const db = betterSupabase.connect(powersyncExecutor(powersync));
 * ```
 */
export function powersyncExecutor(
  db: PowerSyncDatabaseLike,
  options: PowerSyncExecutorOptions = {},
): Executor {
  return {
    name: "powersync",
    execute: (op, context) => executeOn(db, op, context, options),
  };
}
