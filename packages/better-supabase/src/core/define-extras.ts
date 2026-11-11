import type { SchemaMeta } from "../schema/types.ts";
import type { ConnectOptions } from "./define-types.ts";
import type { ErrorMapper } from "./errors.ts";
import type { EventHub as EventHubType } from "./events.ts";
import type { Executor } from "./executor.ts";
import type { AnyPlugin, RequestContext } from "./plugin.ts";
import type { ReadSet } from "./read-set.ts";
import type { Result } from "./result.ts";
import type { OperationRunner } from "./runner.ts";
import type { SearchInput } from "./search.ts";
import type { ReadSetEntry } from "./spec.ts";

import { batchingExecutor } from "./batch.ts";
import { dbDecoder } from "./db-decode.ts";
import { searchTable } from "./db-search.ts";
import { runSpec } from "./define-lazy.ts";
import { NO_PLUGINS } from "./define-plugins.ts";
import { dbError } from "./errors.ts";
import { EventHub } from "./events.ts";
import { openGates } from "./gates.ts";
import { bindParams, checkParams, isReadSet } from "./read-set.ts";
import { AsyncResult, err, ok } from "./result.ts";
import { decodeRpcResult, rpcFunction } from "./rpc-result.ts";
import { isFunctionSpec, isQuerySpec } from "./spec.ts";
import { StatsRecorder, recordStats } from "./stats.ts";

/** What the extras need from the db the connection runtime is building. */
export interface ExtrasScope {
  readonly db: Record<string, unknown>;
  readonly meta: SchemaMeta;
  readonly events: EventHubType;
  readonly plugins: readonly AnyPlugin[];
  readonly given: RequestContext;
  readonly context: RequestContext;
  readonly base: Executor;
  /** The executor after the plugins' wrappers, before stats. */
  readonly wrapped: Executor;
  readonly executor: Executor;
  readonly runner: OperationRunner;
  readonly errorMappers: readonly ErrorMapper[];
  readonly recorder: unknown;
  /** Builds a sibling db over another executor, plugin set or event hub. */
  readonly derive: (options: {
    readonly executor: Executor;
    readonly plugins: readonly AnyPlugin[];
    readonly recorder: unknown;
    readonly events?: EventHubType;
    /** Replaces the caller's context; the sibling then runs without tuning. */
    readonly given?: RequestContext;
  }) => Record<string, unknown>;
}

/**
 * The db methods the browser client leaves out so its bundle stays small:
 * `$many`, `$decodeReadSet`, `$search`, `$stats` and `$decode`, plus the stats
 * recording they report. The server, the adapters and the testing helpers
 * install them through `provideConnectionRuntime()`.
 */
export interface DbExtras {
  /** A recorder for one connection. */
  recorder(options: ConnectOptions): unknown;
  /** Wraps the executor so every call is counted. */
  record(executor: Executor, recorder: unknown): Executor;
  attach(scope: ExtrasScope): void;
}

/**
 * Decodes what a read-set function returned, with the rows run through the
 * specs.
 */
async function decodeReadSet(
  scope: ExtrasScope,
  set: ReadSet,
  specs: Readonly<Record<string, ReadSetEntry>>,
  data: unknown,
  decodeEvents: () => EventHubType,
): Promise<Result<Record<string, unknown>>> {
  const { meta } = scope;

  // SAFETY: the read set function returns one rows and count object per spec key.
  const payload = (data ?? {}) as Record<
    string,
    { rows?: Record<string, unknown>[] | null; count?: number | null } | null
  >;

  // The specs run one at a time, so one decoding db serves them all: its
  // executor answers with the rows of the spec being decoded.
  let rows: Record<string, unknown>[] = [];
  let count: number | null = null;

  const stub: Executor = {
    name: "read-set",
    execute: (op) => {
      if (op.kind === "select" && op.single) {
        if (rows.length > 1) {
          return Promise.resolve(
            err(dbError("multiple_rows", `Expected one ${op.table.key} row`)),
          );
        }

        if (rows.length === 0 && op.single === "one") {
          return Promise.resolve(
            err(dbError("not_found", `No ${op.table.key} row matched`)),
          );
        }
      }

      return Promise.resolve(ok({ rows, count }));
    },
  };

  const decoder = scope.derive({
    executor: stub,
    plugins: NO_PLUGINS,
    recorder: new StatsRecorder(),
    events: decodeEvents(),
    given: scope.context,
  });

  const out: Record<string, unknown> = {};

  for (const [key, spec] of Object.entries(specs)) {
    if (spec.gate !== undefined && payload[key] === null) {
      out[key] = null;
      continue;
    }

    if (isFunctionSpec(spec)) {
      if (!Object.hasOwn(payload, key)) {
        return err(
          dbError(
            "unexpected",
            `${set.functionName}() returned no "${key}". Run \`better-supabase gen\` and migrate.`,
          ),
        );
      }

      const fn = meta.functions[spec.name];

      out[key] = decodeRpcResult(
        meta,
        fn ? rpcFunction(meta, spec.name, fn.schema, spec.args) : undefined,
        payload[key],
      );
      continue;
    }

    const entry = payload[key];

    if (!entry) {
      return err(
        dbError(
          "unexpected",
          `${set.functionName}() returned no "${key}". Run \`better-supabase gen\` and migrate.`,
        ),
      );
    }

    rows = entry.rows ?? [];
    count = entry.count ?? null;
    const result = await runSpec(decoder, spec, undefined);

    if (!result.ok) {
      return result;
    }

    out[key] = result.data;
  }

  return ok(out);
}

type RpcCall = (
  name: string,
  args: Readonly<Record<string, unknown>>,
  options?: { signal?: AbortSignal; schema?: string },
) => AsyncResult<unknown>;

function attach(scope: ExtrasScope, decodeEvents: () => EventHubType): void {
  const {
    db,
    meta,
    plugins,
    context,
    base,
    wrapped,
    executor,
    runner,
    errorMappers,
    recorder,
    derive,
  } = scope;

  const many = (
    specs: readonly unknown[],
    signal: AbortSignal | undefined,
    usePlugins: boolean,
  ): AsyncResult<unknown[]> =>
    AsyncResult.from(async () => {
      const invalid = specs.findIndex((spec) => !isQuerySpec(spec));

      if (invalid !== -1) {
        return err(
          dbError(
            "invalid_request",
            `db.$many() entry ${invalid} is not a QuerySpec from betterSupabase.spec`,
          ),
        );
      }

      const active = usePlugins ? plugins : [];
      const batchSource = usePlugins ? wrapped : base;
      const batch = batchSource.batch?.bind(batchSource);

      const batching =
        batch && specs.length > 1
          ? batchingExecutor({ ...base, batch }, specs.length)
          : undefined;

      const target = batching
        ? derive({ executor: batching.executor, plugins: active, recorder })
        : usePlugins
          ? db
          : derive({ executor: base, plugins: NO_PLUGINS, recorder });

      const results = await Promise.all(
        specs.map(async (spec) => {
          try {
            return await runSpec(target, spec, signal);
          } finally {
            batching?.done();
          }
        }),
      );

      const data: unknown[] = [];

      for (const result of results) {
        if (!result.ok) {
          return result;
        }

        data.push(result.data);
      }

      return ok(data);
    });

  const readSet = (
    set: ReadSet,
    values: Readonly<Record<string, unknown>> | undefined,
    signal: AbortSignal | undefined,
  ): AsyncResult<Record<string, unknown>> =>
    AsyncResult.from(async () => {
      const problems = checkParams(set, values);

      if (problems.length > 0) {
        return err(
          dbError(
            "invalid_request",
            `db.$many(${set.name}): ${problems.join(", ")}`,
          ),
        );
      }

      const keys = Object.keys(set.specs);
      const { specs: bound, noCaller } = bindParams(set, values, context);

      if (base.batch || !executor.rpc) {
        if (noCaller) {
          return err(noCaller);
        }

        // SAFETY: $rpc is a function on every db the connection runtime builds.
        const rpc = db["$rpc"] as RpcCall;
        const open = await openGates(rpc, bound, signal);

        if (!open.ok) {
          return open;
        }

        const tableKeys = keys.filter(
          (key) => !isFunctionSpec(bound[key]) && open.data.has(key),
        );

        // The function entries start beside the table batch, not after it.
        const calls = new Map<string, ReturnType<RpcCall>>();

        for (const key of keys) {
          const entry = bound[key];

          if (
            entry !== undefined &&
            isFunctionSpec(entry) &&
            open.data.has(key)
          ) {
            calls.set(
              key,
              rpc(entry.name, entry.args, {
                ...(signal ? { signal } : {}),
                ...(entry.schema === undefined ? {} : { schema: entry.schema }),
              }),
            );
          }
        }

        const result = await many(
          tableKeys.map((key) => bound[key]),
          signal,
          false,
        );

        if (!result.ok) {
          return result;
        }

        const out: Record<string, unknown> = {};

        for (const key of keys) {
          const call = calls.get(key);

          if (!open.data.has(key)) {
            out[key] = null;
          } else if (call === undefined) {
            out[key] = result.data[tableKeys.indexOf(key)];
          } else {
            const called = await call;

            if (!called.ok) {
              return called;
            }

            out[key] = called.data;
          }
        }

        return ok(out);
      }

      const called = await executor.rpc(
        set.functionName,
        { p: values ?? {} },
        {
          schema: "public",
          get: true,
          errorMappers,
          ...(signal ? { signal } : {}),
        },
      );

      if (!called.ok) {
        return called;
      }

      return decodeReadSet(scope, set, bound, called.data, decodeEvents);
    });

  Object.assign(db, {
    $decode: (table: string) => dbDecoder(meta, table),
    $stats: () =>
      // SAFETY: the extras create every recorder this scope carries.
      (recorder as StatsRecorder).snapshot(),
    $decodeReadSet: (
      set: ReadSet,
      values: Readonly<Record<string, unknown>> | undefined,
      payload: unknown,
    ) =>
      AsyncResult.from(async () => {
        const problems = checkParams(set, values);

        if (problems.length > 0) {
          return err(
            dbError(
              "invalid_request",
              `db.$decodeReadSet(${set.name}): ${problems.join(", ")}`,
            ),
          );
        }

        const { specs: bound } = bindParams(set, values, context);

        return decodeReadSet(scope, set, bound, payload, decodeEvents);
      }),
    $many: (target: unknown, ...rest: unknown[]) => {
      if (isReadSet(target)) {
        // SAFETY: the $many overloads take values and options after a read set.
        const [values, options] = rest as [
          Readonly<Record<string, unknown>> | undefined,
          { signal?: AbortSignal } | undefined,
        ];

        return readSet(target, values, options?.signal);
      }

      // SAFETY: the $many overloads take only options after a spec or a list of specs.
      const [options] = rest as [{ signal?: AbortSignal } | undefined];

      if (!Array.isArray(target)) {
        return AsyncResult.err(
          dbError(
            "invalid_request",
            "db.$many() expects an array of specs or a read set",
          ),
        );
      }

      return many(target, options?.signal, true);
    },
    $search: (name: string, args: SearchInput) =>
      searchTable(runner, base, meta, name, args),
  });
}

/** The extras the full connection runtime installs. */
export function dbExtras(): DbExtras {
  return {
    recorder: (options) =>
      new StatsRecorder(options.stats, undefined, options.admin === true),
    record: (executor, recorder) =>
      // SAFETY: recorder() above is the only source of recorders.
      recordStats(executor, recorder as StatsRecorder),
    attach: (scope) => {
      // A hub without listeners, for decoding read-set results.
      let hub: EventHubType | undefined;

      attach(
        scope,
        () => (hub ??= new EventHub(scope.events.logger, scope.events.now)),
      );
    },
  };
}
