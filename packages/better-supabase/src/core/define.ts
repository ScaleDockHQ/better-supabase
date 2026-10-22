import type {
  AnyFunctions,
  AnyModels,
  Schema,
  SchemaMeta,
  TableKey,
} from "../schema/types.ts";
import type { StorageApi } from "../storage/storage-api.ts";
import type { CacheAdapter, CacheTarget } from "./cache.ts";
import type { BucketRegistry } from "./db-buckets.ts";
import type { ConnectOptions, SupabaseOptions } from "./define-types.ts";
import type { DbError, ErrorMapper } from "./errors.ts";
import type { EventHandler, EventName } from "./events.ts";
import type { Executor } from "./executor.ts";
import type {
  AnyPlugin,
  ExtensionOf,
  RequestContext,
  WithExtension,
} from "./plugin.ts";
import type {
  PostgrestClientLike,
  PostgrestExecutorOptions,
} from "./postgrest-executor.ts";
import type { ReadSet } from "./read-set.ts";
import type { Db } from "./repository-types.ts";
import type { Result, ThrowMapper } from "./result.ts";
import type { SearchInput } from "./search.ts";
import type { QuerySpec, Specs } from "./spec.ts";
import type { StandardSchemaV1 } from "./standard.ts";
import type { RequestTuning } from "./timeout.ts";

import { builderFor } from "../ir/build.ts";
import { batchingExecutor } from "./batch.ts";
import { cacheTargetOf, rpcCacheTargets } from "./cache.ts";
import { searchTable } from "./db-search.ts";
import { NO_PLUGINS, isExecutor, keptPlugins } from "./define-plugins.ts";
import { definitionEvents } from "./diagnostics.ts";
import { DbException, dbError } from "./errors.ts";
import { EventHub, errorEvent } from "./events.ts";
import { isRecord } from "./guards.ts";
import { orderPlugins } from "./plugin.ts";
import { postgrestExecutor } from "./postgrest-executor.ts";
import {
  bindParams,
  checkParams,
  containsPlaceholder,
  isReadSet,
} from "./read-set.ts";
import { createRepository } from "./repository.ts";
import { AsyncResult, err, ok, withErrorMapper } from "./result.ts";
import { decodeRpcResult, rpcFunction, rpcSelect } from "./rpc-result.ts";
import { OperationRunner } from "./runner.ts";
import { createSpecs, isQuerySpec, specTables } from "./spec.ts";
import { validate } from "./standard.ts";
import { StatsRecorder, recordStats } from "./stats.ts";
import {
  nowInstant,
  optionalTemporal,
  provideTemporal,
  providedTemporal,
} from "./temporal.ts";
import { deadline, invalidTuning } from "./timeout.ts";

/** What a `Db` was connected to: its client, and the `storage` option. */
interface DbSource {
  readonly client: unknown;
  readonly storage: StorageApi | undefined;
}

const isStorageApi = (value: unknown): value is StorageApi =>
  isRecord(value) && typeof value["from"] === "function";

/**
 * A supabase-js client builds a new storage client on each read of `storage`,
 * so it is read once per connection.
 */
const clientStorage = new WeakMap<DbSource, StorageApi>();

function storageOf(source: DbSource): StorageApi {
  if (source.storage) {
    return source.storage;
  }

  const cached = clientStorage.get(source);

  if (cached) {
    return cached;
  }

  const client = source.client;
  const storage = isRecord(client) ? client["storage"] : undefined;

  if (isStorageApi(storage)) {
    clientStorage.set(source, storage);

    return storage;
  }

  throw new TypeError(
    "better-supabase: db.$storage needs a client with storage, or connect(executor, context, { storage })",
  );
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
  B = unknown,
> {
  readonly schema: Schema<M, D, F>;
  readonly plugins: readonly AnyPlugin[];
  readonly events: EventHub;
  readonly options: SupabaseOptions;

  constructor(
    schema: Schema<M, D, F>,
    plugins: readonly AnyPlugin[] = [],
    options: SupabaseOptions = {},
    events: EventHub = definitionEvents(options),
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

    if (now) {
      return now;
    }

    return temporal ? () => temporal.Now.instant() : nowInstant;
  }

  /**
   * The `Temporal` this definition uses: the `temporal` option, else the
   * global.
   */
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
   * access token hook output) with `schema`, and whose sessions are typed by
   * it. A token that fails it resolves to `{ kind: 'invalid', reason: 'claims'
   * }`.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).claims(
   *   z.object({ tenant_id: z.uuid() }),
   * );
   * ```
   */
  claims<S extends StandardSchemaV1>(
    schema: S,
  ): BetterSupabase<M, D, F, E, StandardSchemaV1.InferOutput<S>, P, B> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, claims: schema },
      this.events,
    );
  }

  /**
   * Returns a new instance whose sessions parse `user_metadata` with `schema`
   * into a typed `session.profile`. Users can change their metadata with
   * `auth.updateUser()`, so a failure only leaves `profile` undefined (with one
   * warning), and no authorization code reads it. It is for display only:
   * roles, memberships, the tenant and entitlements come from the verified
   * claims, never from `profile`.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).userMetadata(
   *   z.object({ display_name: z.string() }),
   * );
   * ```
   */
  userMetadata<S extends StandardSchemaV1>(
    schema: S,
  ): BetterSupabase<M, D, F, E, C, StandardSchemaV1.InferOutput<S>, B> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, userMetadata: schema },
      this.events,
    );
  }

  /**
   * Returns a new instance whose `.orThrow()` throws `mapper(error)` instead of
   * a `DbException`, and whose results `toBetterResult` maps the same way.
   * Results themselves keep their `DbError`.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).mapError(
   *   (error) => new AppError(error),
   * );
   * ```
   */
  mapError(
    mapper: (error: DbError) => unknown,
  ): BetterSupabase<M, D, F, E, C, P, B> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, throwAs: mapper },
      this.events,
    );
  }

  /**
   * Returns a new instance whose `db.$buckets` has one client per bucket,
   * connected to `db.$storage` so Storage runs as the same caller.
   *
   * ```ts
   * const betterSupabase = defineSupabase(schema).buckets({ logos, avatars });
   * betterSupabase.connect(client).$buckets.logos.signedUrl({ ... });
   * ```
   */
  buckets<const R extends BucketRegistry>(
    registered: R,
  ): BetterSupabase<M, D, F, E, C, P, R> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, buckets: registered },
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
   * as the repository: `betterSupabase.spec.customers.list({ select: ['id']
   * })`.
   */
  get spec(): Specs<M, E> {
    // SAFETY: createSpecs builds one spec builder per table in meta, which is
    // the table set of M.
    this.#specs ??= createSpecs(this.meta) as Specs<M, E>;

    return this.#specs;
  }

  /**
   * App keys of every table a spec reads; mutations of any of them make it
   * stale.
   */
  tablesOf(spec: QuerySpec): string[] {
    return specTables(this.meta, spec);
  }

  /**
   * Returns a new instance with the plugin appended. A plugin with the name of
   * an extension the schema installed replaces it, so
   * `.use(membershipsExtension({ resolve }))` swaps the organization resolver.
   * Any other name installed twice throws.
   */
  use<Q extends AnyPlugin>(
    plugin: Q,
  ): BetterSupabase<M, D, F, WithExtension<E, ExtensionOf<Q>>, C, P, B> {
    const fromSchema = new Set(this.schema.extensions);

    const replaces = this.plugins.some(
      (installed) =>
        installed.name === plugin.name && fromSchema.has(installed),
    );

    return new BetterSupabase(
      this.schema,
      replaces
        ? this.plugins.map((installed) =>
            installed.name === plugin.name && fromSchema.has(installed)
              ? plugin
              : installed,
          )
        : [...this.plugins, plugin],
      this.options,
      this.events,
    );
  }

  /**
   * Declares the tables an RPC writes, so cache adapters and live queries
   * invalidate them after it succeeds.
   *
   * ```ts
   * betterSupabase.defineRpc("archive_customer", {
   *   invalidates: ["customers", "notes"],
   * });
   * ```
   */
  defineRpc(
    name: Extract<keyof F, string>,
    options: { readonly invalidates: readonly TableKey<M>[] },
  ): BetterSupabase<M, D, F, E, C, P, B> {
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

        if (pending) {
          pending.catch((cause: unknown) => {
            report(cause, target.table);
          });
        }
      } catch (cause) {
        report(cause, target.table);
      }
    };

    const offMutation = this.on("mutation", (notice) => {
      invalidate(cacheTargetOf(this.meta, notice));
    });

    const offRpc = this.on("rpc", (notice) => {
      for (const target of rpcCacheTargets(this.meta, notice)) {
        invalidate(target);
      }
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
  ): Db<M, F, E, C, B>;
  connect(
    executor: Executor,
    context?: RequestContext,
    options?: ConnectOptions,
  ): Db<M, F, E, undefined, B>;
  connect(
    source: PostgrestClientLike | Executor,
    context: RequestContext = {},
    options: ConnectOptions = {},
  ): unknown {
    const client = isExecutor(source) ? undefined : source;

    const base =
      options.executor ??
      (isExecutor(source)
        ? source
        : postgrestExecutor(source, this.executorOptions()));

    const recorder = new StatsRecorder(options.stats);

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

  /**
   * The `postgrestExecutor` options this definition implies (`urlLengthLimit`,
   * `postgrestVersion`), for adapters that build their own executor and should
   * chunk reads the same way.
   */
  executorOptions(): PostgrestExecutorOptions {
    const { urlLengthLimit, postgrestVersion } = this.options;

    return {
      ...(urlLengthLimit === undefined ? {} : { urlLengthLimit }),
      ...(postgrestVersion === undefined ? {} : { postgrestVersion }),
    };
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

            return data;
          })
          .mapError((error) => {
            if (events.has("error")) {
              events.emit("error", errorEvent(error));
            }

            return error;
          }),
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

          const result = await many(
            keys.map((key) => bound[key]),
            signal,
            false,
          );

          if (!result.ok) {
            return result;
          }

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
    specs: Readonly<Record<string, QuerySpec>>,
    data: unknown,
  ): Promise<Result<Record<string, unknown>>> {
    // SAFETY: the read set function returns one rows and count object per spec key.
    const payload = (data ?? {}) as Record<
      string,
      { rows?: Record<string, unknown>[] | null; count?: number | null }
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
    const index = spec.method === "get" ? 1 : 0;
    // SAFETY: the options argument of a repository method is an object or undefined.
    args[index] = { ...(args[index] as object | undefined), signal };
  }

  return method(...args);
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
  const args =
    given === undefined
      ? undefined
      : Object.fromEntries(
          Object.entries(given).filter(([, value]) => value !== undefined),
        );

  return AsyncResult.from(async () => {
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

/**
 * Creates the data-layer definition from the generated `schema`, with the
 * repository extensions of the installed blocks (organization scope, trash,
 * `created_by` and `updated_at` stamps, write validation) already in place.
 *
 * ```ts
 * export const betterSupabase = defineSupabase(schema).use(guards());
 * ```
 */
export function defineSupabase<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E = unknown,
>(
  schema: Schema<M, D, F, string, E>,
  options?: SupabaseOptions,
): BetterSupabase<M, D, F, E> {
  return new BetterSupabase(schema, schema.extensions ?? [], options);
}
