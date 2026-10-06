import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { EventHub } from "./events.ts";
import type { ExecuteResult, Executor } from "./executor.ts";

import { type IrBuilder, invalidRequest } from "../ir/build.ts";
import { decodeRows, needsDecoding } from "../ir/codec.ts";
import {
  type Condition,
  type DeleteOp,
  type InsertOp,
  type MutationOp,
  type Operation,
  type OrderTerm,
  type SelectOp,
  type Selection,
  type UpdateOp,
  and,
  column as columnIs,
  not,
  or,
} from "../ir/types.ts";
import { encodeValue } from "../ir/wire.ts";
import { lookupOf } from "../schema/lookup.ts";
import { cloneValue } from "./clone.ts";
import { decodeCursor, encodeCursor } from "./cursor.ts";
import {
  type DbError,
  DbException,
  type ErrorMapper,
  dbError,
} from "./errors.ts";
import {
  type AnyPlugin,
  type CallOptions,
  type HookArgs,
  type MutationEvent,
  type MutationKind,
  type RequestContext,
} from "./plugin.ts";
import { AsyncResult, err, ok, type Result, toDbError } from "./result.ts";

export interface Runtime {
  readonly meta: SchemaMeta;
  readonly builder: IrBuilder;
  readonly executor: Executor;
  readonly plugins: readonly AnyPlugin[];
  readonly context: RequestContext;
  readonly events: EventHub;
  readonly errorMappers: readonly ErrorMapper[];
  readonly now: () => Temporal.Instant;
  /** Rows PostgREST returns at most for one read (`db-max-rows`). */
  readonly maxRows: number;
  /** Tables already warned about truncated reads, shared across connections. */
  readonly truncatedTables: Set<string>;
}

type Args = Readonly<Record<string, unknown>>;
type Row = Record<string, unknown>;

const KNOWN_KEYS = new Set([
  "select",
  "include",
  "where",
  "orderBy",
  "limit",
  "offset",
  "signal",
  "returning",
  "expect",
  "onConflict",
  "ignoreDuplicates",
  "page",
  "size",
  "count",
  "after",
  "mode",
  "data",
  "groupBy",
  "_count",
  "_sum",
  "_avg",
  "_min",
  "_max",
]);

const NO_OPTIONS: CallOptions = Object.freeze({});

function optionsOf(args: Args | undefined): CallOptions {
  if (!args) return NO_OPTIONS;
  let options: Record<string, unknown> | undefined;
  for (const key in args) {
    if (!KNOWN_KEYS.has(key) && Object.hasOwn(args, key))
      (options ??= {})[key] = args[key];
  }
  return options ?? NO_OPTIONS;
}

/** The plugins that implement each per-call hook, found once per plugin list. */
interface Hooks {
  readonly transformQuery: readonly AnyPlugin[];
  readonly beforeMutation: readonly AnyPlugin[];
  readonly afterMutation: readonly AnyPlugin[];
}

const hooksByPlugins = new WeakMap<readonly AnyPlugin[], Hooks>();

function hooksOf(plugins: readonly AnyPlugin[]): Hooks {
  let hooks = hooksByPlugins.get(plugins);
  if (!hooks) {
    hooks = {
      transformQuery: plugins.filter((plugin) => plugin.transformQuery),
      beforeMutation: plugins.filter((plugin) => plugin.beforeMutation),
      afterMutation: plugins.filter((plugin) => plugin.afterMutation),
    };
    hooksByPlugins.set(plugins, hooks);
  }
  return hooks;
}

function isThenable<T>(value: T | PromiseLike<T>): value is PromiseLike<T> {
  return (
    typeof value === "object" &&
    value !== null &&
    "then" in value &&
    typeof value.then === "function"
  );
}

function signalOf(args: Args | undefined): AbortSignal | undefined {
  const signal = args?.["signal"];
  return signal instanceof AbortSignal ? signal : undefined;
}

function cloneRows(rows: readonly Row[]): Row[] {
  // SAFETY: cloneValue keeps the shape of plain objects.
  return rows.map((row) => cloneValue(row) as Row);
}

/** App-cased primary keys of `rows`, or of a `where` that pins the primary key. */
function keysOf(
  op: MutationOp,
  rows: readonly Row[],
): readonly Row[] | undefined {
  const { primaryKey } = op.table;
  if (primaryKey.length === 0) return undefined;
  const fromRows = rows.flatMap((row) =>
    primaryKey.every((name) => row[name] !== undefined && row[name] !== null)
      ? [Object.fromEntries(primaryKey.map((name) => [name, row[name]]))]
      : [],
  );
  if (fromRows.length > 0) return fromRows;
  if (op.kind === "insert") return undefined;
  return keysFromWhere(op.table, op.where);
}

function keysFromWhere(
  table: TableMeta,
  where: Condition | undefined,
): readonly Row[] | undefined {
  if (!where) return undefined;
  const { byDb } = lookupOf(table);
  const pinned = new Map<string, readonly unknown[]>();
  const items: Condition[] = [];
  const flatten = (condition: Condition): void => {
    if (condition.kind === "and") condition.items.forEach(flatten);
    else items.push(condition);
  };
  flatten(where);
  for (const item of items) {
    if (item.kind !== "column") continue;
    const app = byDb.get(item.column)?.[0];
    if (app === undefined || !table.primaryKey.includes(app)) continue;
    if (item.op === "eq") pinned.set(app, [item.value]);
    else if (item.op === "in" && Array.isArray(item.value))
      pinned.set(app, item.value);
  }
  if (pinned.size !== table.primaryKey.length) return undefined;
  const [first, ...rest] = table.primaryKey;
  if (first === undefined) return undefined;
  if (rest.length === 0)
    return (pinned.get(first) ?? []).map((value) => ({ [first]: value }));
  if ([...pinned.values()].some((values) => values.length !== 1))
    return undefined;
  return [
    Object.fromEntries(
      table.primaryKey.map((name) => [name, pinned.get(name)?.[0]]),
    ),
  ];
}

function mutationKind(op: MutationOp): MutationKind {
  if (op.kind === "insert") return op.onConflict ? "upsert" : "insert";
  return op.kind;
}

/** Runs operations through plugins, the executor and the event hub. */
export class OperationRunner {
  readonly runtime: Runtime;
  readonly #hooks: Hooks;

  constructor(runtime: Runtime) {
    this.runtime = runtime;
    this.#hooks = hooksOf(runtime.plugins);
  }

  hookArgs(
    table: TableMeta,
    options: CallOptions,
    signal?: AbortSignal,
  ): HookArgs {
    return {
      table,
      schema: this.runtime.meta,
      context: this.runtime.context,
      options,
      now: this.runtime.now,
      ...(signal ? { signal } : {}),
    };
  }

  async run(
    op: Operation,
    options: CallOptions,
    signal: AbortSignal | undefined,
  ): Promise<Result<ExecuteResult>> {
    const { runtime } = this;
    const hooks = this.#hooks;
    let current = op;
    if (hooks.transformQuery.length > 0 || hooks.beforeMutation.length > 0) {
      const hook = this.hookArgs(op.table, options, signal);
      let active = "";
      try {
        for (const plugin of hooks.transformQuery) {
          active = `plugin "${plugin.name}" transformQuery`;
          current = plugin.transformQuery!(current, hook);
        }
        if (current.kind !== "select") {
          let mutation: MutationOp = current;
          for (const plugin of hooks.beforeMutation) {
            active = `plugin "${plugin.name}" beforeMutation`;
            const next = plugin.beforeMutation!(mutation, hook);
            mutation = isThenable(next) ? await next : next;
          }
          current = mutation;
        }
      } catch (cause) {
        if (cause instanceof DbException)
          return this.fail(op.table, cause.error);
        return this.fail(op.table, {
          ...toDbError(cause),
          details: `${active} threw`,
        });
      }
    }

    const timed = runtime.events.has("query");
    const started = timed ? performance.now() : 0;
    const context = signal
      ? { signal, errorMappers: runtime.errorMappers }
      : { errorMappers: runtime.errorMappers };
    const executed = await runtime.executor.execute(current, context);
    const selection =
      current.kind === "select" ? current.selection : current.returning;
    let result: Result<ExecuteResult> = executed;
    if (executed.ok && selection && needsDecoding(selection)) {
      try {
        result = ok({
          ...executed.data,
          rows: decodeRows(selection, executed.data.rows, true),
        });
      } catch (cause) {
        if (cause instanceof DbException)
          return this.fail(op.table, cause.error);
        throw cause;
      }
    }

    const rows = result.ok ? result.data.rows.length : 0;
    const truncated =
      current.kind === "select" &&
      current.limit === undefined &&
      current.single === undefined &&
      !current.head &&
      rows >= runtime.maxRows;
    if (truncated && !runtime.truncatedTables.has(op.table.key)) {
      runtime.truncatedTables.add(op.table.key);
      runtime.events.logger.warn(
        `a read on ${op.table.key} returned ${rows} rows, the maxRows cap; add a limit or use paginate()`,
        { table: op.table.key, maxRows: runtime.maxRows },
      );
    }
    if (timed) {
      runtime.events.emit("query", {
        table: op.table.key,
        operation: current.kind,
        ok: result.ok,
        durationMs: performance.now() - started,
        rows,
        truncated,
      });
    }
    if (!result.ok) return this.fail(op.table, result.error);

    if (current.kind !== "select") {
      await this.afterMutation(current, result.data);
    }
    return result;
  }

  private async afterMutation(
    op: MutationOp,
    data: ExecuteResult,
  ): Promise<void> {
    const { runtime } = this;
    const plugins = this.#hooks.afterMutation;
    const listening = runtime.events.has("mutation");
    if (plugins.length === 0 && !listening) return;
    const kind = mutationKind(op);
    const rows = cloneRows(data.rows);
    const keys = keysOf(op, rows);
    const { tenant } = runtime.context;
    const event: MutationEvent = {
      table: op.table,
      kind,
      intent: op.intent ?? kind,
      rows,
      ...(keys ? { keys } : {}),
      ...(tenant === undefined ? {} : { tenant }),
      context: runtime.context,
    };
    for (const plugin of plugins) {
      try {
        const pending = plugin.afterMutation!(event);
        if (isThenable(pending)) await pending;
      } catch (cause) {
        runtime.events.logger.error(
          `plugin "${plugin.name}" afterMutation threw`,
          { cause },
        );
      }
    }
    if (listening) {
      runtime.events.emit("mutation", {
        table: op.table.key,
        kind: event.kind,
        ...(event.intent ? { intent: event.intent } : {}),
        rows: event.rows,
        ...(event.keys ? { keys: event.keys } : {}),
        ...(event.tenant === undefined ? {} : { tenant: event.tenant }),
        context: event.context,
      });
    }
  }

  fail<T>(table: TableMeta, error: DbError): Result<T> {
    const withTable = error.table ? error : { ...error, table: table.key };
    if (this.runtime.events.has("error"))
      this.runtime.events.emit("error", { table: table.key, error: withTable });
    return err(withTable);
  }
}

const sensitiveByTable = new WeakMap<TableMeta, ReadonlySet<string>>();

/** Database names of the table's `config.sensitive` columns. */
function sensitiveColumnsOf(table: TableMeta): ReadonlySet<string> {
  let sensitive = sensitiveByTable.get(table);
  if (!sensitive) {
    sensitive = new Set(
      lookupOf(table)
        .entries.filter(([, column]) => column.sensitive)
        .map(([, column]) => column.db),
    );
    sensitiveByTable.set(table, sensitive);
  }
  return sensitive;
}

/** Creates the runtime repository object for one table. */
export function createRepository(
  runner: OperationRunner,
  table: TableMeta,
): Record<string, unknown> {
  const { builder } = runner.runtime;
  const sensitiveDb = sensitiveColumnsOf(table);

  // SAFETY: the select option of every read method is a column list.
  const selection = (args: Args | undefined): Selection =>
    builder.selection(
      table,
      args?.["select"] as readonly string[] | undefined,
      args?.["include"],
    );

  const selectOp = (
    args: Args | undefined,
    patch: Partial<SelectOp> = {},
  ): SelectOp => ({
    kind: "select",
    table,
    selection: selection(args),
    where: builder.where(table, args?.["where"]),
    orderBy: builder.orderBy(table, args?.["orderBy"]),
    limit: typeof args?.["limit"] === "number" ? args["limit"] : undefined,
    offset: typeof args?.["offset"] === "number" ? args["offset"] : undefined,
    count: undefined,
    head: false,
    single: undefined,
    ...patch,
  });

  /** Writes return every column but the sensitive ones unless they are asked for. */
  const returning = (args: Args | undefined): Selection | undefined => {
    if (args?.["returning"] === false) return undefined;
    const all = selection(args);
    if (args?.["select"] !== undefined || args?.["sensitive"] === true)
      return all;
    const columns = all.columns.filter(
      (entry) => !sensitiveDb.has(entry.column),
    );
    return columns.length === all.columns.length ? all : { ...all, columns };
  };

  const run = (
    op: Operation,
    args: Args | undefined,
  ): Promise<Result<ExecuteResult>> =>
    runner.run(op, optionsOf(args), signalOf(args));

  let primaryOrder: readonly OrderTerm[] | undefined;
  /** `primaryKey` holds app names; order terms take database names. */
  const defaultOrder = (): readonly OrderTerm[] =>
    (primaryOrder ??= table.primaryKey.map((name): OrderTerm => ({
      column: builder.column(table, name),
      direction: "asc",
    })));

  const notFound = <T>(): Result<T> =>
    runner.fail(table, dbError("not_found", `No ${table.key} row matched`));

  const base = {
    $tableName: table.key,
    $meta: table,

    findMany(args?: Args) {
      return AsyncResult.from(async () => {
        const op = selectOp(args);
        const ordered =
          op.orderBy.length > 0 || table.primaryKey.length === 0
            ? op
            : { ...op, orderBy: defaultOrder() };
        const result = await run(ordered, args);
        return result.ok ? ok(result.data.rows) : result;
      });
    },

    findFirst(args?: Args) {
      return AsyncResult.from(async () => {
        const result = await run(selectOp(args, { limit: 1 }), args);
        return result.ok ? ok(result.data.rows[0] ?? null) : result;
      });
    },

    findUnique(args: Args) {
      return AsyncResult.from(async () => {
        const op = selectOp(args, {
          where: builder.uniqueKey(table, args["where"]),
          limit: 1,
        });
        const result = await run(op, args);
        return result.ok ? ok(result.data.rows[0] ?? null) : result;
      });
    },

    findById(id: unknown, args?: Args) {
      return AsyncResult.from(async () => {
        const op = selectOp(args, {
          where: builder.primaryKey(table, id),
          limit: 1,
        });
        const result = await run(op, args);
        if (!result.ok) return result;
        const row = result.data.rows[0];
        return row ? ok(row) : notFound();
      });
    },

    count(args?: Args) {
      return AsyncResult.from(async () => {
        const mode = args?.["mode"];
        const op = selectOp(
          { where: args?.["where"] },
          {
            selection: { columns: [], includes: [] },
            count: mode === "planned" || mode === "estimated" ? mode : "exact",
            head: true,
          },
        );
        const result = await run(op, args);
        return result.ok ? ok(result.data.count ?? 0) : result;
      });
    },

    aggregate(args: Args) {
      return AsyncResult.from(async () => {
        const aggregation = builder.aggregation(table, args);
        const orderBy = builder.orderBy(table, args["orderBy"]);
        const grouped = new Set(aggregation.columns.map((c) => c.column));
        const loose = orderBy.find((term) => !grouped.has(term.column));
        if (loose) {
          return runner.fail(
            table,
            dbError(
              "invalid_request",
              `aggregate on "${table.key}" can only sort by groupBy columns, not "${loose.column}"`,
            ),
          );
        }
        const op = selectOp(
          {
            where: args["where"],
            limit: args["limit"],
            offset: args["offset"],
          },
          { selection: aggregation, orderBy },
        );
        const result = await run(op, args);
        if (!result.ok) return result;
        if (args["groupBy"] !== undefined) return ok(result.data.rows);
        // Without groups the database returns one row, unless nothing can match.
        return ok(
          result.data.rows[0] ?? decodeRows(aggregation, [{}])[0] ?? {},
        );
      });
    },

    exists(args?: Args) {
      return AsyncResult.from(async () => {
        const columns = table.primaryKey
          .slice(0, 1)
          .map((alias) => builder.selectColumn(table, alias));
        const op = selectOp(
          { where: args?.["where"] },
          {
            selection: { columns, includes: [] },
            limit: 1,
          },
        );
        const result = await run(op, args);
        return result.ok ? ok(result.data.rows.length > 0) : result;
      });
    },

    paginate(args: Args) {
      return AsyncResult.from(async () =>
        "after" in args ? cursorPage(args) : offsetPage(args),
      );
    },

    create(data: unknown, args?: Args) {
      return AsyncResult.from(async () => {
        const op = insertOp([data], args, undefined);
        const result = await run(op, args);
        if (!result.ok) return result;
        return ok(
          args?.["returning"] === false ? null : (result.data.rows[0] ?? null),
        );
      });
    },

    createMany(rows: readonly unknown[], args?: Args) {
      return AsyncResult.from(async () => {
        if (rows.length === 0)
          return ok(args?.["returning"] === false ? { count: 0 } : []);
        const result = await run(insertOp(rows, args, undefined), args);
        if (!result.ok) return result;
        return ok(
          args?.["returning"] === false
            ? { count: result.data.count ?? rows.length }
            : result.data.rows,
        );
      });
    },

    update(id: unknown, patch: unknown, args?: Args) {
      return AsyncResult.from(async () => {
        const key = and(
          builder.primaryKey(table, id),
          builder.where(table, args?.["where"]),
        );
        const expect = args?.["expect"]
          ? builder.where(table, args["expect"])
          : undefined;
        const op: UpdateOp = {
          kind: "update",
          table,
          set: builder.row(table, patch, "update"),
          where: and(key, expect),
          returning: returning(args),
        };
        const result = await run(op, args);
        if (!result.ok) return result;
        const affected = op.returning
          ? result.data.rows.length
          : (result.data.count ?? 0);
        if (affected === 0) {
          if (!expect) return notFound();
          const exists = await run(
            selectOp(undefined, {
              where: key,
              selection: { columns: [], includes: [] },
              count: "exact",
              head: true,
            }),
            args,
          );
          if (exists.ok && (exists.data.count ?? 0) > 0) {
            return runner.fail(
              table,
              dbError(
                "stale",
                `The ${table.key} row changed since it was read`,
              ),
            );
          }
          return notFound();
        }
        return ok(op.returning ? (result.data.rows[0] ?? null) : null);
      });
    },

    updateMany(args: Args) {
      return AsyncResult.from(async () => {
        const rows = args["returning"] === true;
        const op: UpdateOp = {
          kind: "update",
          table,
          set: builder.row(table, args["data"], "update"),
          where: builder.where(table, args["where"]),
          returning: rows ? returning(args) : undefined,
        };
        const result = await run(op, args);
        if (!result.ok) return result;
        return ok(rows ? result.data.rows : { count: result.data.count ?? 0 });
      });
    },

    upsert(data: unknown, args?: Args) {
      return AsyncResult.from(async () => {
        const op = insertOp(
          [data],
          args,
          conflictColumns(args?.["onConflict"]),
        );
        const result = await run(op, args);
        if (!result.ok) return result;
        return ok(
          args?.["returning"] === false ? null : (result.data.rows[0] ?? null),
        );
      });
    },

    upsertMany(rows: readonly unknown[], args?: Args) {
      return AsyncResult.from(async () => {
        if (rows.length === 0)
          return ok(args?.["returning"] === false ? { count: 0 } : []);
        const op = insertOp(rows, args, conflictColumns(args?.["onConflict"]));
        const result = await run(op, args);
        if (!result.ok) return result;
        return ok(
          args?.["returning"] === false
            ? { count: result.data.count ?? rows.length }
            : result.data.rows,
        );
      });
    },

    delete(id: unknown, args?: Args) {
      return AsyncResult.from(async () => {
        const op: DeleteOp = {
          kind: "delete",
          table,
          where: builder.primaryKey(table, id),
          returning: builder.selection(table, table.primaryKey, undefined),
        };
        const result = await run(op, args);
        if (!result.ok) return result;
        return (result.data.count ?? result.data.rows.length) === 0
          ? notFound()
          : ok(undefined);
      });
    },

    deleteMany(args: Args) {
      return AsyncResult.from(async () => {
        const where = builder.where(table, args["where"]);
        if (!where) {
          return runner.fail(
            table,
            dbError("invalid_request", 'deleteMany needs a non-empty "where"'),
          );
        }
        const rows = args["returning"] === true;
        const op: DeleteOp = {
          kind: "delete",
          table,
          where,
          returning: rows ? returning(args) : undefined,
        };
        // Plugins that rewrite the delete (softDelete) read this to keep RETURNING.
        const result = await runner.run(
          op,
          rows ? { ...optionsOf(args), returning: true } : optionsOf(args),
          signalOf(args),
        );
        if (!result.ok) return result;
        return ok(rows ? result.data.rows : { count: result.data.count ?? 0 });
      });
    },
  };

  function insertOp(
    rows: readonly unknown[],
    args: Args | undefined,
    conflict: readonly string[] | undefined,
  ): InsertOp {
    const built = rows.map((row) => builder.row(table, row));
    return {
      kind: "insert",
      table,
      rows: conflict && built.length > 1 ? byKey(built, conflict) : built,
      returning: returning(args),
      onConflict: conflict
        ? {
            columns: conflict,
            action: args?.["ignoreDuplicates"] === true ? "ignore" : "update",
          }
        : undefined,
      defaultToNull: false,
    };
  }

  function conflictColumns(target: unknown): readonly string[] {
    if (target === undefined || target === "primaryKey") {
      return table.primaryKey.map((name) => builder.column(table, name));
    }
    if (typeof target === "string") {
      const columns = table.uniqueKeys[target];
      if (!columns)
        invalidRequest(
          `Unknown unique key "${target}" on "${table.key}"`,
          table.key,
        );
      return columns.map((name) => builder.column(table, name));
    }
    if (Array.isArray(target)) {
      return target.map((name: unknown) => builder.column(table, String(name)));
    }
    return invalidRequest(`Invalid onConflict on "${table.key}"`, table.key);
  }

  function pageWindow(
    args: Args,
  ): { size: number; offset: number } | { invalid: string } {
    if (args["offset"] !== undefined || args["limit"] !== undefined) {
      if (args["page"] !== undefined || args["size"] !== undefined) {
        return { invalid: 'Pass "offset" and "limit" or "page" and "size"' };
      }
      const limit = Number(args["limit"]);
      if (!Number.isInteger(limit) || limit < 1) {
        return { invalid: '"limit" must be a positive integer' };
      }
      const offset = Number(args["offset"]);
      if (!Number.isInteger(offset) || offset < 0) {
        return { invalid: '"offset" must be a non-negative integer' };
      }
      return { size: limit, offset };
    }
    const size = Number(args["size"]);
    if (!Number.isInteger(size) || size < 1) {
      return { invalid: '"size" must be a positive integer' };
    }
    const number = args["page"] === undefined ? 1 : Number(args["page"]);
    if (!Number.isInteger(number) || number < 1) {
      return { invalid: '"page" must be a positive integer' };
    }
    return { size, offset: (number - 1) * size };
  }

  async function offsetPage(args: Args): Promise<Result<unknown>> {
    const window = pageWindow(args);
    if ("invalid" in window) {
      return runner.fail(table, dbError("invalid_request", window.invalid));
    }
    const { size, offset } = window;
    const number = Math.floor(offset / size) + 1;
    const count = args["count"];
    const orderBy = builder.orderBy(table, args["orderBy"]);
    const op = selectOp(args, {
      orderBy:
        orderBy.length > 0 || table.primaryKey.length === 0
          ? orderBy
          : defaultOrder(),
      limit: size + 1,
      lookAhead: true,
      offset,
      count:
        count === "exact" || count === "planned" || count === "estimated"
          ? count
          : undefined,
    });
    const result = await run(op, args);
    if (!result.ok) return result;
    const rows = result.data.rows;
    const total = result.data.count;
    return ok({
      items: rows.slice(0, size),
      page: {
        number,
        size,
        total,
        pages: total === null ? null : Math.max(1, Math.ceil(total / size)),
        hasMore: rows.length > size,
      },
    });
  }

  async function cursorPage(args: Args): Promise<Result<unknown>> {
    const size = Number(args["size"]);
    if (!Number.isInteger(size) || size < 1) {
      return runner.fail(
        table,
        dbError("invalid_request", '"size" must be a positive integer'),
      );
    }
    const orderBy = withTieBreaker(builder.orderBy(table, args["orderBy"]));
    const base = selection(args);
    const { selection: withSort, added } = ensureColumns(base, orderBy);

    let after: Condition | undefined;
    if (typeof args["after"] === "string") {
      const values = decodeCursor(args["after"]);
      if (!values || values.length !== orderBy.length) {
        return runner.fail(table, dbError("invalid_request", "Invalid cursor"));
      }
      const { byDb } = lookupOf(table);
      after = keysetCondition(
        orderBy,
        values,
        (name) => byDb.get(name)?.[1].nullable ?? true,
      );
    }

    const op = selectOp(args, {
      selection: withSort,
      where: and(builder.where(table, args["where"]), after),
      orderBy,
      limit: size + 1,
      lookAhead: true,
      offset: undefined,
    });
    const result = await run(op, args);
    if (!result.ok) return result;

    const rows = result.data.rows.slice(0, size);
    const hasMore = result.data.rows.length > size;
    const last = rows.at(-1);
    const aliases = new Map(
      withSort.columns.map((entry) => [entry.column, entry.alias]),
    );
    const nextCursor =
      hasMore && last
        ? encodeCursor(
            orderBy.map((term) =>
              encodeValue(last[aliases.get(term.column) ?? term.column]),
            ),
          )
        : null;
    return ok({
      items: added.length > 0 ? rows.map((row) => strip(row, added)) : rows,
      nextCursor,
      hasMore,
    });
  }

  function withTieBreaker(orderBy: readonly OrderTerm[]): OrderTerm[] {
    const terms = [...orderBy];
    for (const name of table.primaryKey) {
      const column = builder.column(table, name);
      if (!terms.some((term) => term.column === column)) {
        terms.push({ column, direction: terms[0]?.direction ?? "asc" });
      }
    }
    return terms;
  }

  function ensureColumns(
    base: Selection,
    orderBy: readonly OrderTerm[],
  ): { selection: Selection; added: string[] } {
    const columns = [...base.columns];
    const selected = new Set(columns.map((entry) => entry.column));
    const { byDb } = lookupOf(table);
    const added: string[] = [];
    for (const term of orderBy) {
      if (selected.has(term.column)) continue;
      const alias = byDb.get(term.column)?.[0] ?? term.column;
      columns.push({ alias, column: term.column });
      selected.add(term.column);
      added.push(alias);
    }
    return { selection: { columns, includes: base.includes }, added };
  }

  return base;
}

function strip(row: Row, keys: readonly string[]): Row {
  const copy: Row = {};
  for (const key in row) {
    if (!keys.includes(key) && Object.hasOwn(row, key)) copy[key] = row[key];
  }
  return copy;
}

/**
 * Rows in conflict-key order, so concurrent upserts lock the same rows in
 * the same order instead of deadlocking.
 */
function byKey(
  rows: readonly Readonly<Record<string, unknown>>[],
  columns: readonly string[],
): Readonly<Record<string, unknown>>[] {
  const compare = (left: unknown, right: unknown): number => {
    if (left === right) return 0;
    if (left === null || left === undefined) return 1;
    if (right === null || right === undefined) return -1;
    if (typeof left === "number" && typeof right === "number")
      return left - right;
    if (typeof left === "bigint" && typeof right === "bigint")
      return left < right ? -1 : 1;
    const a = String(left);
    const b = String(right);
    return a < b ? -1 : a > b ? 1 : 0;
  };
  // Keys are read once per row, not once per comparison.
  const keyed = rows.map((row) => ({
    row,
    key: columns.map((column) => {
      const value = row[column];
      return typeof value === "object" && value !== null
        ? String(value)
        : value;
    }),
  }));
  keyed.sort((left, right) => {
    for (let index = 0; index < columns.length; index++) {
      const order = compare(left.key[index], right.key[index]);
      if (order !== 0) return order;
    }
    return 0;
  });
  return keyed.map((entry) => entry.row);
}

/**
 * The rows after the cursor `values` in `orderBy` order, as an OR of ANDs:
 * `a > x or (a = x and b > y)`. The SQL compiler sends that shape as the row
 * comparison `(a, b) > (x, y)`. Nulls sort where Postgres puts them: last
 * for `asc`, first for `desc`, unless the term says otherwise.
 */
function keysetCondition(
  orderBy: readonly OrderTerm[],
  values: readonly unknown[],
  nullable: (column: string) => boolean,
): Condition {
  const isNull = (name: string): Condition => columnIs(name, "is", null);
  const branches = orderBy.flatMap((term, index): Condition[] => {
    const value = values[index];
    const nullsFirst =
      (term.nulls ?? (term.direction === "desc" ? "first" : "last")) ===
      "first";
    const after = columnIs(
      term.column,
      term.direction === "asc" ? "gt" : "lt",
      value,
    );
    const step =
      value === null
        ? nullsFirst
          ? not(isNull(term.column))
          : undefined
        : nullsFirst || !nullable(term.column)
          ? after
          : or(after, isNull(term.column));
    if (!step) return [];
    const equal = orderBy
      .slice(0, index)
      .map((prev, prevIndex) =>
        values[prevIndex] === null
          ? isNull(prev.column)
          : columnIs(prev.column, "eq", values[prevIndex]),
      );
    return [and(...equal, step) ?? step];
  });
  // A null in the last nulls-last term leaves nothing after the cursor.
  return branches.length > 0
    ? or(...branches)
    : columnIs(orderBy[0]?.column ?? "", "in", []);
}
