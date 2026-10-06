import type { SelectOp } from "../ir/types.ts";
import type {
  AnyFunctions,
  AnyModels,
  Schema,
  SchemaMeta,
  TableKey,
} from "../schema/types.ts";
import type { Executor } from "./executor.ts";
import type { Logger } from "./logger.ts";
import type { Db } from "./repository-types.ts";

import { builderFor } from "../ir/build.ts";
import { batchingExecutor } from "./batch.ts";
import {
  type CacheAdapter,
  type CacheTarget,
  cacheTargetOf,
  rpcCacheTargets,
} from "./cache.ts";
import {
  type DbError,
  DbException,
  type ErrorMapper,
  dbError,
} from "./errors.ts";
import { type EventHandler, EventHub, type EventName } from "./events.ts";
import {
  type AnyPlugin,
  type ExtensionOf,
  type WithExtension,
  orderPlugins,
  type RequestContext,
} from "./plugin.ts";
import {
  type PostgrestClientLike,
  postgrestExecutor,
} from "./postgrest-executor.ts";
import {
  bindParams,
  checkParams,
  containsPlaceholder,
  isReadSet,
  type ReadSet,
} from "./read-set.ts";
import { createRepository, OperationRunner } from "./repository.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  type ThrowMapper,
  withErrorMapper,
} from "./result.ts";
import { decodeRpcResult } from "./rpc-result.ts";
import { type SearchInput, vectorLiteral } from "./search.ts";
import {
  createSpecs,
  isQuerySpec,
  type QuerySpec,
  type Specs,
  specTables,
} from "./spec.ts";
import { type StandardSchemaV1, validate } from "./standard.ts";
import { recordStats, StatsRecorder } from "./stats.ts";
import {
  nowInstant,
  optionalTemporal,
  providedTemporal,
  provideTemporal,
} from "./temporal.ts";

export interface SupabaseOptions {
  /** Clock used by plugins (timestamps, soft delete). */
  readonly now?: () => Temporal.Instant;
  /**
   * The `Temporal` namespace, for runtimes without a global one (Hermes,
   * Node 24) when patching `globalThis` is not an option:
   * `import { Temporal } from 'temporal-polyfill'`. Defaults to `globalThis.Temporal`.
   */
  readonly temporal?: typeof Temporal;
  /** Extra error mappers, run before plugin mappers. */
  readonly errors?: readonly ErrorMapper[];
  /** Receives errors from event handlers, hooks and cache adapters. Defaults to `console`. */
  readonly logger?: Logger;
  /** RPCs that change tables, keyed by function name. Prefer `betterSupabase.defineRpc()`. */
  readonly rpc?: Readonly<Record<string, RpcDefinition>>;
  /** Builds the error `.orThrow()` throws. Prefer `betterSupabase.mapError()`. */
  readonly throwAs?: ThrowMapper;
  /** Validates verified JWT claims on the server. Prefer `betterSupabase.claims()`, which also types them. */
  readonly claims?: StandardSchemaV1;
  /** Parses `user_metadata` into `session.profile`. Prefer `betterSupabase.userMetadata()`, which also types it. */
  readonly userMetadata?: StandardSchemaV1;
  /**
   * PostgREST's `db-max-rows`: the most rows one read returns. An unbounded
   * `findMany` that returns this many sets `truncated` on the `query` event
   * and logs a warning once per table. Defaults to 1000, the hosted default.
   */
  readonly maxRows?: number;
}

export interface ConnectOptions {
  /** Also records this connection's calls into a request-wide recorder. */
  readonly stats?: StatsRecorder;
  /**
   * Runs operations instead of the client's own executor, while `$client`
   * stays the client (e.g. routing reads to a replica).
   */
  readonly executor?: Executor;
}

export interface RpcDefinition {
  /** App keys of the tables the function writes; their cached reads are invalidated on success. */
  readonly invalidates: readonly string[];
}

function isExecutor(value: unknown): value is Executor {
  // SAFETY: value is a non-null object here, and each property read is type-checked.
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as Executor).execute === "function" &&
    typeof (value as Executor).name === "string"
  );
}

/** The installed plugins named in `keep`; a name that isn't installed throws, so a typo can't drop tracing silently. */
function keptPlugins(
  plugins: readonly AnyPlugin[],
  keep: readonly string[],
): readonly AnyPlugin[] {
  for (const name of keep) {
    if (!plugins.some((plugin) => plugin.name === name)) {
      throw new TypeError(
        `better-supabase: $withoutPlugins({ keep }) names "${name}", which is not installed. Installed: ${plugins.map((plugin) => plugin.name).join(", ") || "none"}`,
      );
    }
  }
  return plugins.filter((plugin) => keep.includes(plugin.name));
}

/**
 * The isomorphic definition of your data layer: schema plus plugins. Holds no
 * secrets and no connection; `connect()` binds it to a client per request.
 */
export class BetterSupabase<
  M extends AnyModels = AnyModels,
  D = unknown,
  F extends AnyFunctions = AnyFunctions,
  E = unknown,
  C = unknown,
  P = unknown,
> {
  readonly schema: Schema<M, D, F>;
  readonly plugins: readonly AnyPlugin[];
  readonly events: EventHub;
  readonly options: SupabaseOptions;

  constructor(
    schema: Schema<M, D, F>,
    plugins: readonly AnyPlugin[] = [],
    options: SupabaseOptions = {},
    events: EventHub = new EventHub(options.logger),
  ) {
    const names = new Set<string>();
    for (const plugin of plugins) {
      // oxlint-disable-next-line typescript/no-unnecessary-condition -- plugins from JavaScript can target another API version.
      if (plugin.apiVersion !== 1) {
        throw new TypeError(
          `better-supabase: plugin "${plugin.name}" targets plugin API v${String(plugin.apiVersion)}; this version supports v1`,
        );
      }
      if (names.has(plugin.name)) {
        throw new TypeError(
          `better-supabase: plugin "${plugin.name}" is already installed`,
        );
      }
      names.add(plugin.name);
    }
    this.schema = schema;
    this.plugins = orderPlugins(plugins);
    this.options = options;
    this.events = events;
    const { temporal } = options;
    if (temporal !== undefined) {
      const previous = providedTemporal();
      if (previous !== undefined && previous !== temporal) {
        events.logger.warn(
          "defineSupabase got a different `temporal` namespace than the one already provided; decoded rows, jobs and webhooks in this process now use the newer one. Pass the same namespace to every definition.",
        );
      }
      provideTemporal(temporal);
    }
  }

  get meta(): SchemaMeta {
    return this.schema.meta;
  }

  /** The `now` option, else this definition's own `Temporal` clock. */
  #now(): () => Temporal.Instant {
    const { now, temporal } = this.options;
    if (now) return now;
    return temporal ? () => temporal.Now.instant() : nowInstant;
  }

  /** The `Temporal` this definition uses: the `temporal` option, else the global. */
  get temporal(): typeof Temporal | undefined {
    return this.options.temporal ?? optionalTemporal();
  }

  /** The schema set by `claims()`; its output types `session.claims`. */
  get claimsSchema(): StandardSchemaV1<unknown, C> | undefined {
    // SAFETY: claims() stores the schema whose output is C; the constructor
    // option is untyped.
    return this.options.claims as StandardSchemaV1<unknown, C> | undefined;
  }

  /** The schema set by `userMetadata()`; its output types `session.profile`. */
  get userMetadataSchema(): StandardSchemaV1<unknown, P> | undefined {
    // SAFETY: only `userMetadata()` sets the option, and it fixes `P` to the schema output.
    return this.options.userMetadata as
      | StandardSchemaV1<unknown, P>
      | undefined;
  }

  /**
   * Returns a new instance whose servers validate verified JWT claims (custom
   * access token hook output) with `schema`, and whose sessions are typed by it.
   * A token that fails it resolves to `{ kind: 'invalid', reason: 'claims' }`.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).claims(z.object({ tenant_id: z.uuid() }));
   * ```
   */
  claims<S extends StandardSchemaV1>(
    schema: S,
  ): BetterSupabase<M, D, F, E, StandardSchemaV1.InferOutput<S>, P> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, claims: schema },
      this.events,
    );
  }

  /**
   * Returns a new instance whose sessions parse `user_metadata` with
   * `schema` into a typed `session.profile`. Users can change their metadata
   * with `auth.updateUser()`, so a failure only leaves `profile` undefined
   * (with one warning), and no authorization code reads it. It is for
   * display only: roles, memberships, the tenant and entitlements come from
   * the verified claims, never from `profile`.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).userMetadata(z.object({ display_name: z.string() }));
   * ```
   */
  userMetadata<S extends StandardSchemaV1>(
    schema: S,
  ): BetterSupabase<M, D, F, E, C, StandardSchemaV1.InferOutput<S>> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, userMetadata: schema },
      this.events,
    );
  }

  /**
   * Returns a new instance whose `.orThrow()` throws `mapper(error)` instead
   * of a `DbException`, and whose results `toBetterResult` maps the same way.
   * Results themselves keep their `DbError`.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).mapError((error) => new AppError(error));
   * ```
   */
  mapError(
    mapper: (error: DbError) => unknown,
  ): BetterSupabase<M, D, F, E, C, P> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, throwAs: mapper },
      this.events,
    );
  }

  #specs: Specs<M, E> | undefined;
  readonly #truncatedTables = new Set<string>();
  /** A hub without listeners, for decoding read-set results. */
  #decodeEvents: EventHub | undefined;
  /** One getter per table, shared by every db this instance connects. */
  #tables: object | undefined;
  readonly #errorMappers = new WeakMap<
    readonly AnyPlugin[],
    readonly ErrorMapper[]
  >();

  /**
   * Builds serializable `QuerySpec`s with the same arguments and result types
   * as the repository: `betterSupabase.spec.customers.findMany({ select: ['id'] })`.
   */
  get spec(): Specs<M, E> {
    // SAFETY: createSpecs builds one spec builder per table in meta, which is
    // the table set of M.
    this.#specs ??= createSpecs(this.meta) as Specs<M, E>;
    return this.#specs;
  }

  /** App keys of every table a spec reads; mutations of any of them make it stale. */
  tablesOf(spec: QuerySpec): string[] {
    return specTables(this.meta, spec);
  }

  /** Returns a new instance with the plugin appended. */
  use<Q extends AnyPlugin>(
    plugin: Q,
  ): BetterSupabase<M, D, F, WithExtension<E, ExtensionOf<Q>>, C, P> {
    return new BetterSupabase(
      this.schema,
      [...this.plugins, plugin],
      this.options,
      this.events,
    );
  }

  /**
   * Declares the tables an RPC writes, so cache adapters and live queries
   * invalidate them after it succeeds.
   *
   * ```ts
   * betterSupabase.defineRpc('archive_customer', { invalidates: ['customers', 'notes'] });
   * ```
   */
  defineRpc(
    name: Extract<keyof F, string>,
    options: { readonly invalidates: readonly TableKey<M>[] },
  ): BetterSupabase<M, D, F, E, C, P> {
    for (const table of options.invalidates) {
      if (!this.meta.tables[table]) {
        throw new TypeError(
          `better-supabase: defineRpc("${name}") invalidates unknown table "${table}"`,
        );
      }
    }
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, rpc: { ...this.options.rpc, [name]: options } },
      this.events,
    );
  }

  /** Observes queries, mutations, errors, auth and refreshes. */
  on<K extends EventName>(name: K, handler: EventHandler<K>): () => void {
    return this.events.on(name, handler);
  }

  /**
   * Invalidates `adapter` after every mutation in this runtime. Returns a
   * function that detaches it. Adapter failures are logged, never thrown.
   */
  cache(adapter: CacheAdapter): () => void {
    const report = (cause: unknown, table: string): void => {
      this.events.logger.error(`cache adapter "${adapter.name}" failed`, {
        cause,
        table,
      });
    };
    const invalidate = (target: CacheTarget): void => {
      try {
        const pending = adapter.invalidate(target);
        if (pending)
          pending.catch((cause: unknown) => {
            report(cause, target.table);
          });
      } catch (cause) {
        report(cause, target.table);
      }
    };
    const offMutation = this.on("mutation", (notice) => {
      invalidate(cacheTargetOf(this.meta, notice));
    });
    const offRpc = this.on("rpc", (notice) => {
      for (const target of rpcCacheTargets(this.meta, notice))
        invalidate(target);
    });
    return () => {
      offMutation();
      offRpc();
    };
  }

  /**
   * Binds the definition to a supabase-js client (or any `Executor`) and a
   * request context. Cheap: call it once per request.
   */
  connect<C extends PostgrestClientLike>(
    client: C,
    context?: RequestContext,
    options?: ConnectOptions,
  ): Db<M, F, E, C>;
  connect(
    executor: Executor,
    context?: RequestContext,
    options?: ConnectOptions,
  ): Db<M, F, E, undefined>;
  connect(
    source: PostgrestClientLike | Executor,
    context: RequestContext = {},
    options: ConnectOptions = {},
  ): unknown {
    const client = isExecutor(source) ? undefined : source;
    const base =
      options.executor ??
      (isExecutor(source) ? source : postgrestExecutor(source));
    const recorder = new StatsRecorder(options.stats);
    return this.#db(client, base, context, this.plugins, recorder);
  }

  /** The caller's context with every plugin's `context` hook applied. */
  #derive(
    given: RequestContext,
    plugins: readonly AnyPlugin[],
  ): RequestContext {
    let context = given;
    for (const plugin of plugins) {
      if (!plugin.context) continue;
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
    client: unknown,
    base: Executor,
    given: RequestContext,
    plugins: readonly AnyPlugin[],
    recorder: StatsRecorder,
    events: EventHub = this.events,
  ): object {
    const context = this.#derive(given, plugins);
    let executor = base;
    for (const plugin of plugins) {
      if (plugin.wrapExecutor) executor = plugin.wrapExecutor(executor);
    }
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
      truncatedTables: this.#truncatedTables,
    });

    // SAFETY: the prototype only adds the table getters; the own properties
    // below are the $ methods.
    const db = Object.create(this.#tablePrototype()) as Record<string, unknown>;
    dbStates.set(db, { runner, plugins, repositories: new Map() });
    Object.assign(db, {
      $client: client,
      $executor: executor,
      $context: context,
      $rpc: (name: string, ...rest: unknown[]) =>
        rpc(this.schema.meta, executor, errorMappers, name, rest).map(
          (data) => {
            const registered = this.options.rpc?.[name];
            if (registered) {
              this.events.emit("rpc", {
                name,
                invalidates: registered.invalidates,
                context,
              });
            }
            return data;
          },
        ),
      $with: (extra: RequestContext) =>
        this.#db(client, base, { ...given, ...extra }, plugins, recorder),
      $withoutPlugins: (options?: { readonly keep?: readonly string[] }) =>
        this.#db(
          client,
          base,
          given,
          keptPlugins(plugins, options?.keep ?? []),
          recorder,
        ),
      $stats: () => recorder.snapshot(),
      $table: (name: string) => {
        if (!Object.hasOwn(this.meta.tables, name)) {
          throw new TypeError(
            `better-supabase: unknown table "${name}". Known: ${Object.keys(this.meta.tables).join(", ")}`,
          );
        }
        return db[name];
      },
      $run: (spec: unknown, options?: { signal?: AbortSignal }) =>
        runSpec(db, spec, options?.signal),
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
        AsyncResult.from(async () => {
          const table = Object.hasOwn(this.meta.tables, name)
            ? this.meta.tables[name]
            : undefined;
          if (!table) {
            return err(
              dbError(
                "invalid_request",
                `db.$search(): unknown table "${name}"`,
              ),
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
          const query = vectorLiteral(args.vector);
          const k = args.k ?? 10;
          if (query === undefined || !Number.isInteger(k) || k < 1) {
            return err(
              dbError(
                "invalid_input",
                "db.$search() needs a vector of finite numbers and a positive integer k",
                { table: table.key },
              ),
            );
          }
          const { builder } = runner.runtime;
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
              args: { query, k },
            },
          };
          const result = await runner.run(op, {}, args.signal);
          if (result.ok) return ok(result.data.rows);
          const missing =
            result.error.code === "PGRST202" || result.error.code === "42883";
          return missing
            ? err({
                ...result.error,
                hint: `Add "${table.schema}.${table.name}" to vectorSearch in better-supabase.config.ts and run \`better-supabase sql sync\`.`,
              })
            : result;
        }),
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
        const batch = base.batch?.bind(base);
        const batching =
          batch && specs.length > 1
            ? batchingExecutor({ ...base, batch }, specs.length)
            : undefined;
        // SAFETY: #db returns the repositories indexed by table name, plus the $ methods.
        const target = (
          batching
            ? this.#db(client, batching.executor, given, active, recorder)
            : usePlugins
              ? db
              : this.#db(client, base, given, [], recorder)
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
          if (!result.ok) return result;
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
        const bound = bindParams(set, values ?? {});
        if (base.batch || !executor.rpc) {
          const result = await many(
            keys.map((key) => bound[key]),
            signal,
            false,
          );
          if (!result.ok) return result;
          return ok(
            Object.fromEntries(keys.map((key, i) => [key, result.data[i]])),
          );
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
        if (!called.ok) return called;
        return this.#decodeReadSet(client, context, set, bound, called.data);
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
   * Decodes what a read-set function returned (`{ [key]: { rows, count } }`)
   * by running each spec against those rows, so casing, codecs and
   * aggregates come out exactly as from `db.$run`.
   */
  async #decodeReadSet(
    client: unknown,
    context: RequestContext,
    set: ReadSet,
    specs: Readonly<Record<string, QuerySpec>>,
    data: unknown,
  ): Promise<Result<Record<string, unknown>>> {
    // SAFETY: the read set function returns one rows and count object per spec key.
    const payload = (data ?? {}) as Record<
      string,
      { rows?: Record<string, unknown>[] | null; count?: number | null }
    >;
    const out: Record<string, unknown> = {};
    for (const [key, spec] of Object.entries(specs)) {
      const entry = payload[key];
      if (!entry) {
        return err(
          dbError(
            "unexpected",
            `${set.functionName}() returned no "${key}". Run \`better-supabase gen\` and migrate.`,
          ),
        );
      }
      const rows = entry.rows ?? [];
      const stub: Executor = {
        name: "read-set",
        execute: (op) => {
          if (op.kind === "select" && op.single) {
            if (rows.length > 1)
              return Promise.resolve(
                err(
                  dbError("multiple_rows", `Expected one ${op.table.key} row`),
                ),
              );
            if (rows.length === 0 && op.single === "one")
              return Promise.resolve(
                err(dbError("not_found", `No ${op.table.key} row matched`)),
              );
          }
          return Promise.resolve(ok({ rows, count: entry.count ?? null }));
        },
      };
      // SAFETY: #db returns the repositories indexed by table name, plus the $ methods.
      const decoder = this.#db(
        client,
        stub,
        context,
        [],
        new StatsRecorder(),
        (this.#decodeEvents ??= new EventHub(this.events.logger)),
      ) as Record<string, unknown>;
      const result = await runSpec(decoder, spec, undefined);
      if (!result.ok) return result;
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
    if (this.#tables) return this.#tables;
    const tables = {};
    const throwAs = this.options.throwAs;
    const build = (state: DbState, key: string): Record<string, unknown> => {
      let repository = state.repositories.get(key);
      if (repository) return repository;
      // SAFETY: the prototype only defines getters for keys of meta.tables.
      const table = this.meta.tables[key]!;
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
    for (const key of Object.keys(this.meta.tables)) {
      Object.defineProperty(tables, key, {
        enumerable: true,
        get(this: object) {
          const state = dbStates.get(this);
          return state ? build(state, key) : undefined;
        },
      });
    }
    this.#tables = tables;
    return tables;
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
      if (!methods) continue;
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
    ) => ({
      ...repository,
      ...build(repository),
    });
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
  return function (this: unknown, ...args) {
    const value = method.apply(this, args);
    return value instanceof AsyncResult
      ? withErrorMapper(value, throwAs)
      : value;
  };
}

function runSpec(
  db: Record<string, unknown>,
  spec: unknown,
  signal: AbortSignal | undefined,
): AsyncResult<unknown> {
  if (!isQuerySpec(spec)) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        "db.$run() expects a QuerySpec from betterSupabase.spec",
      ),
    );
  }
  // SAFETY: isQuerySpec checked the spec, so db[spec.table] is a repository or undefined.
  const repository = db[spec.table] as
    | Record<string, (...args: unknown[]) => AsyncResult<unknown>>
    | undefined;
  const method = repository?.[spec.method];
  if (!method) {
    return AsyncResult.err(
      dbError("invalid_request", `Unknown table "${spec.table}" in QuerySpec`),
    );
  }
  if (containsPlaceholder(spec.args)) {
    return AsyncResult.err(
      dbError(
        "invalid_request",
        "This spec comes from a read set and still holds placeholders; run it with db.$many(readSet, params)",
      ),
    );
  }
  const args = [...spec.args];
  if (signal) {
    const index = spec.method === "findById" ? 1 : 0;
    // SAFETY: the options argument of a repository method is an object or undefined.
    args[index] = { ...(args[index] as object | undefined), signal };
  }
  return method(...args);
}

function rpc(
  meta: SchemaMeta,
  executor: Executor,
  errorMappers: readonly ErrorMapper[],
  name: string,
  rest: unknown[],
): AsyncResult<unknown> {
  // SAFETY: the $rpc overloads take args and then options.
  const [args, options] = rest as [
    Readonly<Record<string, unknown>> | undefined,
    (
      | {
          signal?: AbortSignal;
          returns?: StandardSchemaV1;
          schema?: string;
          raw?: boolean;
        }
      | undefined
    ),
  ];
  return AsyncResult.from(async () => {
    if (!executor.rpc) {
      return err(
        dbError(
          "invalid_request",
          `Executor "${executor.name}" does not support rpc()`,
        ),
      );
    }
    const context = {
      schema: options?.schema ?? "public",
      errorMappers,
      ...(options?.signal ? { signal: options.signal } : {}),
    };
    const result = await executor.rpc(name, args ?? {}, context);
    if (!result.ok) return result;
    let data = result.data;
    if (options?.raw !== true) {
      try {
        data = decodeRpcResult(meta, name, context.schema, data);
      } catch (cause) {
        if (cause instanceof DbException) return err(cause.error);
        throw cause;
      }
    }
    if (!options?.returns) return ok(data);
    const checked = await validate(options.returns, data, `${name}() result`);
    return checked.ok ? ok(checked.data) : checked;
  });
}

/**
 * Creates the data-layer definition from the generated `schema`.
 *
 * ```ts
 * export const betterSupabase = defineSupabase(schema).use(timestamps()).use(softDelete());
 * ```
 */
export function defineSupabase<M extends AnyModels, D, F extends AnyFunctions>(
  schema: Schema<M, D, F>,
  options?: SupabaseOptions,
): BetterSupabase<M, D, F> {
  return new BetterSupabase(schema, [], options);
}
