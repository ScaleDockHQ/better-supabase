import type { Executor } from "../../core/executor.ts";
import type { Plugin } from "../../core/plugin.ts";
import type { Operation } from "../../ir/types.ts";

import { definePlugin } from "../../core/plugin.ts";

/**
 * The `metric` function of `@vercel/functions`, typed structurally so the
 * package stays an optional peer: the app imports it and passes it in.
 */
export type VercelMetric = (
  name: string,
  value: number,
  tags?: Record<string, string>,
) => void;

/** The most `metric()` calls one connection makes when `maxCalls` is unset. */
export const DEFAULT_MAX_METRIC_CALLS = 16;

export interface VercelMetricsOptions {
  /**
   * The most `metric()` calls one connection makes, the budget marker included.
   * Every call crosses into the Vercel runtime synchronously, so a page that
   * runs hundreds of queries must not pay for hundreds of samples. A connection
   * is one request in the adapters. Past the cap the plugin drops samples and
   * sends one `<prefix>.budget_exceeded` count as its last call. Failures are
   * sent before the duration of the same call. Defaults to 16.
   */
  readonly maxCalls?: number;
  /** Metric name prefix. Defaults to `better_supabase.db`. */
  readonly prefix?: string;
  /** Tags added to every sample. Keep them low in cardinality. */
  readonly tags?: Readonly<Record<string, string>>;
}

const OPERATION_NAME: { readonly [K in Operation["kind"]]: string } = {
  select: "select",
  insert: "insert",
  update: "update",
  delete: "delete",
};

function operationName(op: Operation): string {
  if (op.kind === "insert" && op.onConflict?.action === "update") {
    return "upsert";
  }

  if (op.kind === "select" && op.head) {
    return "count";
  }

  return OPERATION_NAME[op.kind];
}

/** What a finished call tells the budget: the outcome and, on failure, why. */
interface Outcome {
  readonly error?: string;
}

/**
 * Database query duration and failure counts as Vercel custom metrics, for
 * every repository operation. It measures and forwards: a result, a rejection
 * and a throwing `metric` all reach the caller unchanged (invariant 5). Samples
 * carry the table (or function), the operation and the outcome as tags; filter
 * values and row data never leave the process.
 *
 * ```ts
 * import { metric } from "@vercel/functions";
 *
 * const betterSupabase = createSupabase(schema).use(vercelMetrics(metric));
 * ```
 *
 * Query them with `vc metrics better_supabase.db.duration_ms -a p95 --group-by
 * target`.
 */
export function vercelMetrics(
  metric: VercelMetric,
  options: VercelMetricsOptions = {},
): Plugin<"vercel-metrics"> {
  const prefix = options.prefix ?? "better_supabase.db";
  const base = options.tags ?? {};
  const requested = options.maxCalls ?? DEFAULT_MAX_METRIC_CALLS;
  const cap = Math.max(1, Math.floor(requested));

  return definePlugin({
    name: "vercel-metrics",
    enforce: "post",
    wrapExecutor: (executor): Executor => {
      // One executor serves one request's connection, so this is the budget of
      // one request.
      let used = 0;
      let broken = false;
      let exceeded = false;

      const send = (
        name: string,
        value: number,
        tags: Record<string, string>,
      ) => {
        if (broken) {
          return;
        }

        used += 1;

        try {
          metric(name, value, { ...base, ...tags });
        } catch {
          // A metric sink that throws stays out of the caller's way; stop
          // asking it for the rest of this connection.
          broken = true;
        }
      };

      const record = (
        target: string,
        operation: string,
        durationMs: number,
        outcome: Outcome,
      ) => {
        if (broken || exceeded) {
          return;
        }

        const needed = outcome.error === undefined ? 1 : 2;

        if (used + needed > cap - 1) {
          exceeded = true;
          send(`${prefix}.budget_exceeded`, 1, {});

          return;
        }

        const tags = { target, operation };

        if (outcome.error !== undefined) {
          send(`${prefix}.errors`, 1, { ...tags, kind: outcome.error });
        }

        send(`${prefix}.duration_ms`, durationMs, {
          ...tags,
          outcome: outcome.error === undefined ? "ok" : "error",
        });
      };

      const measured = async <T>(
        target: string,
        operation: string,
        run: () => Promise<T>,
        outcomeOf: (result: T) => Outcome,
      ): Promise<T> => {
        const started = performance.now();

        try {
          const result = await run();

          record(
            target,
            operation,
            performance.now() - started,
            outcomeOf(result),
          );

          return result;
        } catch (cause) {
          record(target, operation, performance.now() - started, {
            error: "exception",
          });
          throw cause;
        }
      };

      const rpc = executor.rpc?.bind(executor);
      const batch = executor.batch?.bind(executor);

      return {
        ...executor,
        name: executor.name,
        execute: (op, context) =>
          measured(
            op.table.name,
            operationName(op),
            () => executor.execute(op, context),
            (result) => (result.ok ? {} : { error: result.error.kind }),
          ),
        ...(rpc
          ? {
              rpc: (name, args, context) =>
                measured(
                  name,
                  "rpc",
                  () => rpc(name, args, context),
                  (result) => (result.ok ? {} : { error: result.error.kind }),
                ),
            }
          : {}),
        ...(batch
          ? {
              batch: (ops, context) =>
                measured(
                  "batch",
                  "batch",
                  () => batch(ops, context),
                  (results) => {
                    const failure = results.find((result) => !result.ok);

                    return failure?.ok === false
                      ? { error: failure.error.kind }
                      : {};
                  },
                ),
            }
          : {}),
      };
    },
  });
}
