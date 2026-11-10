import type { SchemaMeta } from "../schema/types.ts";
import type { DbSource } from "./db-storage.ts";
import type { ConnectOptions } from "./define-types.ts";
import type { Definition } from "./define.ts";
import type { ErrorMapper } from "./errors.ts";
import type { EventHub as EventHubType } from "./events.ts";
import type { Executor } from "./executor.ts";
import type { GateRpc } from "./gates.ts";
import type { AnyPlugin, RequestContext } from "./plugin.ts";
import type { PostgrestClientLike } from "./postgrest-executor.ts";
import type { ReadSet } from "./read-set.ts";
import type { Result, ThrowMapper } from "./result.ts";
import type { SearchInput } from "./search.ts";
import type { ReadSetEntry } from "./spec.ts";
import type { StandardSchemaV1 } from "./standard.ts";
import type { RequestTuning } from "./timeout.ts";

import { builderFor } from "../ir/build.ts";
import { encodeArguments } from "../ir/wire.ts";
import { addLazyTable } from "../schema/define.ts";
import { decodeRpcReturn } from "../schema/rpc-returns.ts";
import { batchingExecutor } from "./batch.ts";
import { blocksPrototype } from "./db-blocks.ts";
import { dbDecoder } from "./db-decode.ts";
import { searchTable } from "./db-search.ts";
import { storageOf } from "./db-storage.ts";
import { ensureFunctions, lazyRepository, runSpec } from "./define-lazy.ts";
import { NO_PLUGINS, isExecutor, keptPlugins } from "./define-plugins.ts";
import { installConnectionRuntime } from "./define.ts";
import { DbException, dbError } from "./errors.ts";
import { EventHub, errorEvent } from "./events.ts";
import { openGates } from "./gates.ts";
import { postgrestExecutor } from "./postgrest-executor.ts";
import { bindParams, checkParams, isReadSet } from "./read-set.ts";
import { createRepository } from "./repository.ts";
import { AsyncResult, err, ok, withErrorMapper } from "./result.ts";
import { decodeRpcResult, rpcFunction, rpcSelect } from "./rpc-result.ts";
import { OperationRunner } from "./runner.ts";
import { isFunctionSpec, isQuerySpec } from "./spec.ts";
import { validate } from "./standard.ts";
import { StatsRecorder, recordStats } from "./stats.ts";
import { nowInstant } from "./temporal.ts";
import { deadline, invalidTuning } from "./timeout.ts";

/**
 * Turns one definition into a `db`. Lives apart from the definition class so
 * entries that only read the definition (the proxy, the sessions runtime) do
 * not bundle the executor, the query builder and the repositories.
 */
class Connector {
  readonly #truncatedTables = new Set<string>();
  /** A hub without listeners, for decoding read-set results. */
  #decodeEvents: EventHubType | undefined;
  /** One getter per table, shared by every db this instance connects. */
  #tables: object | undefined;
  readonly #errorMappers = new WeakMap<
    readonly AnyPlugin[],
    readonly ErrorMapper[]
  >();

  readonly definition: Definition;

  constructor(definition: Definition) {
    this.definition = definition;
  }

  get meta(): SchemaMeta {
    return this.definition.meta;
  }

  get options(): Definition["options"] {
    return this.definition.options;
  }

  get events(): EventHubType {
    return this.definition.events;
  }

  get plugins(): readonly AnyPlugin[] {
    return this.definition.plugins;
  }

  get schema(): Definition["schema"] {
    return this.definition.schema;
  }

  /** The `now` option, else this definition's own `Temporal` clock. */
  #now(): () => Temporal.Instant {
    const { now, temporal } = this.options;

    if (now) {
      return now;
    }

    return temporal ? () => temporal.Now.instant() : nowInstant;
  }

  connect(
    source: PostgrestClientLike | Executor,
    context: RequestContext,
    options: ConnectOptions,
  ): unknown {
    const client = isExecutor(source) ? undefined : source;

    const base =
      options.executor ??
      (isExecutor(source)
        ? source
        : postgrestExecutor(source, this.definition.executorOptions()));

    const recorder = new StatsRecorder(
      options.stats,
      undefined,
      options.admin === true,
    );

    const tuning: RequestTuning = {
      ...(options.timeout === undefined ? {} : { timeout: options.timeout }),
      ...(options.retry === undefined ? {} : { retry: options.retry }),
    };

    return this.#db(
      { client, storage: options.storage },
      base,
      context,
      this.plugins,
      recorder,
      tuning,
    );
  }
  /** The caller's context with every plugin's `context` hook applied. */
  #derive(
    given: RequestContext,
    plugins: readonly AnyPlugin[],
  ): RequestContext {
    let context = given;

    for (const plugin of plugins) {
      if (!plugin.context) {
        continue;
      }

      try {
        context = plugin.context(context, { schema: this.meta });
      } catch (cause) {
        this.events.logger.error(`plugin "${plugin.name}" context threw`, {
          cause,
        });
      }
    }

    return context;
  }

  #db(
    source: DbSource,
    base: Executor,
    given: RequestContext,
    plugins: readonly AnyPlugin[],
    recorder: StatsRecorder,
    tuning: RequestTuning = {},
    events: EventHub = this.events,
  ): object {
    const context = this.#derive(given, plugins);
    let executor = base;

    for (const plugin of plugins) {
      if (plugin.wrapExecutor) {
        executor = plugin.wrapExecutor(executor);
      }
    }

    const wrapped = executor;
    executor = recordStats(executor, recorder);
    const errorMappers = this.#errorMappersFor(plugins);

    const runner = new OperationRunner({
      meta: this.meta,
      builder: builderFor(this.meta),
      executor,
      plugins,
      context,
      events,
      errorMappers,
      now: this.#now(),
      maxRows: this.options.maxRows ?? 1000,
      truncation: this.options.truncation ?? "error",
      truncatedTables: this.#truncatedTables,
      tuning,
    });

    // SAFETY: the prototype only adds the table getters; the own properties
    // below are the $ methods.
    const db = Object.create(this.#tablePrototype()) as Record<string, unknown>;
    dbStates.set(db, { runner, plugins, repositories: new Map() });
    const { client } = source;
    Object.defineProperty(db, "$storage", {
      get: () => storageOf(source),
      configurable: true,
    });
    const { buckets } = this.options;

    if (buckets) {
      let connected: Record<string, unknown> | undefined;

      Object.defineProperty(db, "$buckets", {
        get: () => {
          connected ??= Object.fromEntries(
            Object.entries(buckets).map(([name, bucket]) => [
              name,
              bucket.connect(storageOf(source)),
            ]),
          );

          return connected;
        },
        configurable: true,
      });
    }

    Object.assign(db, {
      $client: client,
      $executor: executor,
      $context: context,
      $rpc: (name: string, ...rest: unknown[]) =>
        rpc(this.schema.meta, executor, errorMappers, tuning, name, rest)
          .map((data) => {
            const registered = this.options.rpc?.[name];

            if (registered) {
              this.events.emit("rpc", {
                name,
                invalidates: registered.invalidates,
                context,
              });
            }

            return decodeRpcReturn(name, data);
          })
          .mapError((error) => {
            if (events.has("error")) {
              events.emit("error", errorEvent(error));
            }

            return error;
          }),
      $decode: (table: string) => dbDecoder(this.meta, table),
      $with: (extra: RequestContext) =>
        this.#db(
          source,
          base,
          { ...given, ...extra },
          plugins,
          recorder,
          tuning,
        ),
      $withoutPlugins: (options?: { readonly keep?: readonly string[] }) =>
        this.#db(
          source,
          base,
          given,
          keptPlugins(plugins, options?.keep ?? []),
          recorder,
          tuning,
        ),
      $stats: () => recorder.snapshot(),
      $table: (name: string) => {
        // A table the server loads on first use (ADR 0611) is known by its loader.
        const known = [
          ...Object.keys(this.meta.tables),
          ...Object.keys(this.meta.tableLoaders ?? {}),
        ];

        if (!known.includes(name)) {
          throw new TypeError(
            `better-supabase: unknown table "${name}". Known: ${known.join(", ")}`,
          );
        }

        return db[name];
      },
      $run: (spec: unknown, options?: { signal?: AbortSignal }) =>
        runSpec(db, spec, options?.signal),
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

          return this.#decodeReadSet(source, context, set, bound, payload);
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
        searchTable(runner, base, this.meta, name, args),
    });

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

        // SAFETY: #db returns the repositories indexed by table name, plus the $ methods.
        const target = (
          batching
            ? this.#db(
                source,
                batching.executor,
                given,
                active,
                recorder,
                tuning,
              )
            : usePlugins
              ? db
              : this.#db(source, base, given, NO_PLUGINS, recorder, tuning)
        ) as Record<string, unknown>;

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

          const open = await openGates(
            // SAFETY: $rpc is a function on every db this method builds.
            db["$rpc"] as GateRpc,
            bound,
            signal,
          );

          if (!open.ok) {
            return open;
          }

          const tableKeys = keys.filter(
            (key) => !isFunctionSpec(bound[key]) && open.data.has(key),
          );

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
            const entry = bound[key];

            if (!open.data.has(key)) {
              out[key] = null;
            } else if (isFunctionSpec(entry)) {
              // SAFETY: $rpc is a function on every db this method builds.
              const called = await (
                db["$rpc"] as (
                  name: string,
                  args: Readonly<Record<string, unknown>>,
                  options?: { signal?: AbortSignal; schema?: string },
                ) => AsyncResult<unknown>
              )(entry.name, entry.args, {
                ...(signal ? { signal } : {}),
                ...(entry.schema === undefined ? {} : { schema: entry.schema }),
              });

              if (!called.ok) {
                return called;
              }

              out[key] = called.data;
            } else {
              out[key] = result.data[tableKeys.indexOf(key)];
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

        return this.#decodeReadSet(source, context, set, bound, called.data);
      });

    const throwAs = this.options.throwAs;

    if (throwAs) {
      for (const name of ["$rpc", "$run", "$many", "$search"]) {
        // SAFETY: these $ methods are functions on every db this method builds.
        db[name] = mapThrows(db[name] as AnyMethod, throwAs);
      }
    }

    return db;
  }

  /**
   * Decodes what a read-set function returned (`{ [key]: { rows, count } }`) by
   * running each spec against those rows, so casing, codecs and aggregates come
   * out exactly as from `db.$run`.
   */
  async #decodeReadSet(
    source: DbSource,
    context: RequestContext,
    set: ReadSet,
    specs: Readonly<Record<string, ReadSetEntry>>,
    data: unknown,
  ): Promise<Result<Record<string, unknown>>> {
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

    // SAFETY: #db returns the repositories indexed by table name, plus the $ methods.
    const decoder = this.#db(
      source,
      stub,
      context,
      NO_PLUGINS,
      new StatsRecorder(),
      {},
      (this.#decodeEvents ??= new EventHub(
        this.events.logger,
        this.events.now,
      )),
    ) as Record<string, unknown>;

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

        const fn = this.meta.functions[spec.name];

        out[key] = decodeRpcResult(
          this.meta,
          fn
            ? rpcFunction(this.meta, spec.name, fn.schema, spec.args)
            : undefined,
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

  #errorMappersFor(plugins: readonly AnyPlugin[]): readonly ErrorMapper[] {
    let mappers = this.#errorMappers.get(plugins);

    if (!mappers) {
      mappers = [
        ...(this.options.errors ?? []),
        ...plugins.flatMap((plugin) =>
          plugin.mapError ? [plugin.mapError] : [],
        ),
      ];
      this.#errorMappers.set(plugins, mappers);
    }

    return mappers;
  }

  #tablePrototype(): object {
    if (this.#tables) {
      return this.#tables;
    }

    const tables = {};
    const throwAs = this.options.throwAs;

    const build = (state: DbState, key: string): Record<string, unknown> => {
      let repository = state.repositories.get(key);

      if (repository) {
        return repository;
      }

      const table = this.meta.tables[key];

      if (table === undefined) {
        const load = this.meta.tableLoaders?.[key];

        if (load === undefined) {
          throw new TypeError(`better-supabase: unknown table "${key}"`);
        }

        return lazyRepository(this.meta, state, key, load, build, (table) => {
          this.registerTable(table);
        });
      }

      repository = this.#repository(state.runner, key, table, state.plugins);

      if (throwAs) {
        for (const [name, method] of Object.entries(repository)) {
          if (typeof method === "function" && name !== "extend") {
            // SAFETY: the typeof check above narrows method to a function.
            repository[name] = mapThrows(method as AnyMethod, throwAs);
          }
        }
      }

      state.repositories.set(key, repository);

      return repository;
    };

    this.#build = build;

    for (const key of new Set([
      ...Object.keys(this.meta.tables),
      ...Object.keys(this.meta.tableLoaders ?? {}),
    ])) {
      this.#defineTable(tables, key);
    }

    const { blocks, temporal } = this.options;

    this.#tables =
      blocks === undefined
        ? tables
        : blocksPrototype(
            blocks,
            tables,
            Object.keys(this.meta.tables),
            this.events,
            temporal,
          );

    return this.#tables;
  }

  #build:
    | ((state: DbState, key: string) => Record<string, unknown>)
    | undefined;

  #defineTable(tables: object, key: string): void {
    const build = this.#build;

    Object.defineProperty(tables, key, {
      enumerable: true,
      configurable: true,
      get(this: object) {
        const state = dbStates.get(this);

        return state && build ? build(state, key) : undefined;
      },
    });
  }

  /**
   * Adds a table to a definition whose schema sets `lazyTables`, so a `db` made
   * earlier reads it too. The split layout's browser client calls it through
   * `client.table(customers)`; everything else lists its tables.
   */
  registerTable(table: SchemaMeta["tables"][string]): void {
    if (addLazyTable(this.meta, table) && this.#tables !== undefined) {
      this.#defineTable(this.#tables, table.key);
    }
  }

  #repository(
    runner: OperationRunner,
    key: string,
    table: SchemaMeta["tables"][string],
    plugins: readonly AnyPlugin[],
  ): Record<string, unknown> {
    const repository = createRepository(runner, table);

    for (const plugin of plugins) {
      // SAFETY: a repository is a map of methods; plugins receive it untyped.
      const methods = plugin.repository?.({
        table,
        base: repository as Readonly<
          Record<string, (...args: never[]) => unknown>
        >,
      });

      if (!methods) {
        continue;
      }

      for (const [name, method] of Object.entries(methods)) {
        if (name in repository) {
          throw new TypeError(
            `better-supabase: plugin "${plugin.name}" redefines "${key}.${name}"`,
          );
        }

        repository[name] = method;
      }
    }

    repository["extend"] = (
      build: (base: Record<string, unknown>) => Record<string, unknown>,
    ) => ({ ...repository, ...build(repository) });

    return repository;
  }
}

type AnyMethod = (...args: unknown[]) => unknown;

/** What a db's table getters need; the getters live on a shared prototype. */
interface DbState {
  readonly runner: OperationRunner;
  readonly plugins: readonly AnyPlugin[];
  readonly repositories: Map<string, Record<string, unknown>>;
}

const dbStates = new WeakMap<object, DbState>();

function mapThrows(method: AnyMethod, throwAs: ThrowMapper): AnyMethod {
  return function mapped(this: unknown, ...args) {
    const value = method.apply(this, args);

    return value instanceof AsyncResult
      ? withErrorMapper(value, throwAs)
      : value;
  };
}

function rpc(
  meta: SchemaMeta,
  executor: Executor,
  errorMappers: readonly ErrorMapper[],
  defaults: RequestTuning,
  name: string,
  rest: unknown[],
): AsyncResult<unknown> {
  // SAFETY: the $rpc overloads take args and then options.
  const [given, options] = rest as [
    Readonly<Record<string, unknown>> | undefined,
    (
      | {
          signal?: AbortSignal;
          timeout?: number;
          retry?: boolean;
          returns?: StandardSchemaV1;
          schema?: string;
          raw?: boolean;
        }
      | undefined
    ),
  ];

  // An optional argument left `undefined` is omitted, so a GET call never
  // sends the string "undefined" and the function default applies.
  const args = given === undefined ? undefined : encodeArguments(given);

  return AsyncResult.from(async () => {
    await ensureFunctions(meta);

    if (!executor.rpc) {
      return err(
        dbError(
          "unsupported",
          `Executor "${executor.name}" does not support rpc()`,
        ),
      );
    }

    const tuning: RequestTuning = {
      ...defaults,
      ...(options?.timeout === undefined ? {} : { timeout: options.timeout }),
      ...(options?.retry === undefined ? {} : { retry: options.retry }),
    };

    const invalid = invalidTuning(tuning);

    if (invalid) {
      return err(dbError("invalid_request", invalid));
    }

    const limit = deadline(options?.signal, tuning.timeout);
    const schema = options?.schema ?? "public";
    const fn = rpcFunction(meta, name, schema, args ?? {});
    const select = options?.raw === true ? undefined : rpcSelect(meta, fn);

    const context = {
      schema,
      errorMappers,
      ...(limit.signal ? { signal: limit.signal } : {}),
      ...(tuning.retry === undefined ? {} : { retry: tuning.retry }),
      ...(fn ? { function: fn } : {}),
      ...(select ? { select } : {}),
    };

    let result: Result<unknown>;

    try {
      result = await executor.rpc(name, args ?? {}, context);
    } finally {
      limit.clear();
    }

    if (!result.ok && limit.timedOut()) {
      return err(
        dbError("timeout", `The request timed out after ${tuning.timeout} ms`),
      );
    }

    if (!result.ok) {
      return result;
    }

    let data = result.data;

    if (options?.raw !== true) {
      try {
        data = decodeRpcResult(meta, fn, data);
      } catch (cause) {
        if (cause instanceof DbException) {
          return err(cause.error);
        }

        throw cause;
      }
    }

    if (!options?.returns) {
      return ok(data);
    }

    const checked = await validate(options.returns, data, `${name}() result`);

    return checked.ok ? ok(checked.data) : checked;
  });
}

const connectors = new WeakMap<Definition, Connector>();

function connectorOf(definition: Definition): Connector {
  let connector = connectors.get(definition);

  if (!connector) {
    connector = new Connector(definition);
    connectors.set(definition, connector);
  }

  return connector;
}

/** Installs the connection runtime on `Definition.connect`. */
export function provideConnectionRuntime(): void {
  installConnectionRuntime({
    connect: (definition, source, context, options) =>
      connectorOf(definition).connect(source, context, options),
    registerTable: (definition, table) => {
      connectorOf(definition).registerTable(table);
    },
  });
}
