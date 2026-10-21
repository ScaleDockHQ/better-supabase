import type { IrBuilder } from "../ir/build.ts";
import type { MutationOp, Operation } from "../ir/types.ts";
import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { ExecuteContext, ExecuteResult, Executor } from "./executor.ts";
import type {
  AnyPlugin,
  CallOptions,
  HookArgs,
  MutationEvent,
  MutationKind,
  RequestContext,
} from "./plugin.ts";

import { decodeRows, needsDecoding } from "../ir/codec.ts";
import { cloneValue } from "./clone.ts";
import {
  DbException,
  dbError,
  type DbError,
  type ErrorMapper,
} from "./errors.ts";
import { errorEvent, type EventHub } from "./events.ts";
import { err, ok, toDbError, type Result } from "./result.ts";
import { keysOf } from "./row-keys.ts";
import {
  NO_TUNING,
  deadline,
  invalidTuning,
  type RequestTuning,
} from "./timeout.ts";

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
  /** The connection's `timeout` and `retry`; a call's own settings replace them. */
  readonly tuning?: RequestTuning;
}

export type Args = Readonly<Record<string, unknown>>;

export type Row = Record<string, unknown>;

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
  "timeout",
  "retry",
  "maxAffected",
  "defaultToNull",
]);

const NO_OPTIONS: CallOptions = Object.freeze({});

export function optionsOf(args: Args | undefined): CallOptions {
  if (!args) {
    return NO_OPTIONS;
  }

  let options: Record<string, unknown> | undefined;

  for (const key in args) {
    if (!KNOWN_KEYS.has(key) && Object.hasOwn(args, key)) {
      (options ??= {})[key] = args[key];
    }
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

export function signalOf(args: Args | undefined): AbortSignal | undefined {
  const signal = args?.["signal"];

  return signal instanceof AbortSignal ? signal : undefined;
}

function cloneRows(rows: readonly Row[]): Row[] {
  // SAFETY: cloneValue keeps the shape of plain objects.
  return rows.map((row) => cloneValue(row) as Row);
}

function mutationKind(op: MutationOp): MutationKind {
  if (op.kind === "insert") {
    return op.onConflict ? "upsert" : "insert";
  }

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
    tuning: RequestTuning | { readonly invalid: string } = NO_TUNING,
  ): Promise<Result<ExecuteResult>> {
    const { runtime } = this;
    const hooks = this.#hooks;

    if ("invalid" in tuning) {
      return this.fail(op.table, dbError("invalid_request", tuning.invalid));
    }

    const { timeout, retry } = { ...runtime.tuning, ...tuning };
    const invalid = invalidTuning({ timeout, retry });

    if (invalid) {
      return this.fail(op.table, dbError("invalid_request", invalid));
    }

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
        if (cause instanceof DbException) {
          return this.fail(op.table, cause.error);
        }

        return this.fail(op.table, {
          ...toDbError(cause),
          details: `${active} threw`,
        });
      }
    }

    // PostgREST answers an empty PATCH with no rows, which reads as not_found.
    if (current.kind === "update" && Object.keys(current.set).length === 0) {
      return this.fail(
        op.table,
        dbError(
          "invalid_request",
          `The update on "${op.table.key}" sets no columns`,
        ),
      );
    }

    const timed = runtime.events.has("query");
    const started = timed ? performance.now() : 0;
    const executed = await this.#execute(current, signal, timeout, retry);

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
        if (cause instanceof DbException) {
          return this.fail(op.table, cause.error);
        }

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

    if (!result.ok) {
      return this.fail(op.table, result.error);
    }

    if (current.kind !== "select") {
      await this.afterMutation(current, result.data);
    }

    return result;
  }

  /**
   * Runs `op` without plugins or decoding, with the connection's timeout and
   * retry, and fails on `table`: for reads the library makes itself, such as
   * the scores of `db.$search({ score: true })`.
   */
  async runInternal(
    op: Operation,
    table: TableMeta,
    signal: AbortSignal | undefined,
  ): Promise<Result<ExecuteResult>> {
    const { timeout, retry } = this.runtime.tuning ?? NO_TUNING;
    const invalid = invalidTuning({ timeout, retry });

    if (invalid) {
      return this.fail(table, dbError("invalid_request", invalid));
    }

    const executed = await this.#execute(op, signal, timeout, retry);

    return executed.ok
      ? executed
      : this.fail(table, { ...executed.error, table: table.key });
  }

  async #execute(
    op: Operation,
    signal: AbortSignal | undefined,
    timeout: number | undefined,
    retry: RequestTuning["retry"],
  ): Promise<Result<ExecuteResult>> {
    const limit = deadline(signal, timeout);

    const context: ExecuteContext = {
      errorMappers: this.runtime.errorMappers,
      ...(limit.signal ? { signal: limit.signal } : {}),
      ...(retry === undefined ? {} : { retry }),
    };

    let executed: Result<ExecuteResult>;

    try {
      executed = await this.runtime.executor.execute(op, context);
    } finally {
      limit.clear();
    }

    if (!executed.ok && limit.timedOut()) {
      return err(
        dbError("timeout", `The request timed out after ${timeout} ms`),
      );
    }

    return executed;
  }

  private async afterMutation(
    op: MutationOp,
    data: ExecuteResult,
  ): Promise<void> {
    const { runtime } = this;
    const plugins = this.#hooks.afterMutation;
    const listening = runtime.events.has("mutation");

    if (plugins.length === 0 && !listening) {
      return;
    }

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

        if (isThenable(pending)) {
          await pending;
        }
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

    if (this.runtime.events.has("error")) {
      this.runtime.events.emit("error", errorEvent(withTable, table.key));
    }

    return err(withTable);
  }
}
