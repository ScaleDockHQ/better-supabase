import type {
  AnyFunctions,
  AnyModels,
  Schema,
  SchemaMeta,
  TableKey,
} from '../schema/types.ts';
import type { Executor } from './executor.ts';
import type { Logger } from './logger.ts';
import type { Db } from './repository-types.ts';

import { IrBuilder } from '../ir/build.ts';
import { batchingExecutor } from './batch.ts';
import {
  type CacheAdapter,
  type CacheTarget,
  cacheTargetOf,
  rpcCacheTargets,
} from './cache.ts';
import { type DbError, type ErrorMapper, dbError } from './errors.ts';
import { type EventHandler, EventHub, type EventName } from './events.ts';
import {
  type AnyPlugin,
  type ExtensionOf,
  type WithExtension,
  orderPlugins,
  type RequestContext,
} from './plugin.ts';
import {
  type PostgrestClientLike,
  postgrestExecutor,
} from './postgrest-executor.ts';
import {
  bindParams,
  checkParams,
  containsPlaceholder,
  isReadSet,
  type ReadSet,
} from './read-set.ts';
import { createRepository, OperationRunner } from './repository.ts';
import {
  AsyncResult,
  err,
  ok,
  type Result,
  type ThrowMapper,
  withErrorMapper,
} from './result.ts';
import {
  createSpecs,
  isQuerySpec,
  type QuerySpec,
  type Specs,
  specTables,
} from './spec.ts';
import { type StandardSchemaV1, validate } from './standard.ts';
import { recordStats, StatsRecorder } from './stats.ts';

export interface DefineSupabaseOptions {
  /** Clock used by plugins (timestamps, soft delete). */
  readonly now?: () => Date;
  /** Extra error mappers, run before plugin mappers. */
  readonly errors?: readonly ErrorMapper[];
  /** Receives errors from event handlers, hooks and cache adapters. Defaults to `console`. */
  readonly logger?: Logger;
  /** RPCs that change tables, keyed by function name. Prefer `sb.defineRpc()`. */
  readonly rpc?: Readonly<Record<string, RpcDefinition>>;
  /** Builds the error `.orThrow()` throws. Prefer `sb.mapError()`. */
  readonly throwAs?: ThrowMapper;
  /** Validates verified JWT claims on the server. Prefer `sb.claims()`, which also types them. */
  readonly claims?: StandardSchemaV1;
}

export interface ConnectOptions {
  /** Also records this connection's calls into a request-wide recorder. */
  readonly stats?: StatsRecorder;
}

export interface RpcDefinition {
  /** App keys of the tables the function writes; their cached reads are invalidated on success. */
  readonly invalidates: readonly string[];
}

function isExecutor(value: unknown): value is Executor {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as Executor).execute === 'function' &&
    typeof (value as Executor).name === 'string'
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
> {
  readonly schema: Schema<M, D, F>;
  readonly plugins: readonly AnyPlugin[];
  readonly events: EventHub;
  readonly options: DefineSupabaseOptions;

  constructor(
    schema: Schema<M, D, F>,
    plugins: readonly AnyPlugin[] = [],
    options: DefineSupabaseOptions = {},
    events: EventHub = new EventHub(options.logger),
  ) {
    this.schema = schema;
    this.plugins = orderPlugins(plugins);
    this.options = options;
    this.events = events;
  }

  get meta(): SchemaMeta {
    return this.schema.meta;
  }

  /** The schema set by `claims()`; its output types `session.claims`. */
  get claimsSchema(): StandardSchemaV1<unknown, C> | undefined {
    return this.options.claims as StandardSchemaV1<unknown, C> | undefined;
  }

  /**
   * Returns a new instance whose servers validate verified JWT claims (custom
   * access token hook output) with `schema`, and whose sessions are typed by it.
   * A token that fails it resolves to `{ kind: 'invalid', reason: 'claims' }`.
   *
   * ```ts
   * const sb = defineSupabase(schema).claims(z.object({ tenant_id: z.uuid() }));
   * ```
   */
  claims<S extends StandardSchemaV1>(
    schema: S,
  ): BetterSupabase<M, D, F, E, StandardSchemaV1.InferOutput<S>> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, claims: schema },
      this.events,
    );
  }

  /**
   * Returns a new instance whose `.orThrow()` throws `mapper(error)` instead
   * of a `DbException`, and whose results `toBetterResult` maps the same way.
   * Results themselves keep their `DbError`.
   *
   * ```ts
   * const sb = defineSupabase(schema).mapError((error) => new AppError(error));
   * ```
   */
  mapError(mapper: (error: DbError) => unknown): BetterSupabase<M, D, F, E, C> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, throwAs: mapper },
      this.events,
    );
  }

  #specs: Specs<M, E> | undefined;

  /**
   * Builds serializable `QuerySpec`s with the same arguments and result types
   * as the repository: `sb.spec.customers.findMany({ select: ['id'] })`.
   */
  get spec(): Specs<M, E> {
    this.#specs ??= createSpecs(this.meta) as Specs<M, E>;
    return this.#specs;
  }

  /** App keys of every table a spec reads; mutations of any of them make it stale. */
  tablesOf(spec: QuerySpec): string[] {
    return specTables(this.meta, spec);
  }

  /** Returns a new instance with the plugin appended. */
  use<P extends AnyPlugin>(
    plugin: P,
  ): BetterSupabase<M, D, F, WithExtension<E, ExtensionOf<P>>, C> {
    if (plugin.apiVersion !== 1) {
      throw new TypeError(
        `better-supabase: plugin "${plugin.name}" targets plugin API v${String(plugin.apiVersion)}; this version supports v1`,
      );
    }
    if (this.plugins.some((existing) => existing.name === plugin.name)) {
      throw new TypeError(
        `better-supabase: plugin "${plugin.name}" is already installed`,
      );
    }
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
   * sb.defineRpc('archive_customer', { invalidates: ['customers', 'notes'] });
   * ```
   */
  defineRpc(
    name: Extract<keyof F, string>,
    options: { readonly invalidates: readonly TableKey<M>[] },
  ): BetterSupabase<M, D, F, E, C> {
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
          pending.catch((cause: unknown) => report(cause, target.table));
      } catch (cause) {
        report(cause, target.table);
      }
    };
    const offMutation = this.on('mutation', (notice) => {
      invalidate(cacheTargetOf(this.meta, notice));
    });
    const offRpc = this.on('rpc', (notice) => {
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
    const base = isExecutor(source) ? source : postgrestExecutor(source);
    const recorder = new StatsRecorder(options.stats);
    return this.#db(client, base, context, this.plugins, recorder);
  }

  #db(
    client: unknown,
    base: Executor,
    context: RequestContext,
    plugins: readonly AnyPlugin[],
    recorder: StatsRecorder,
    events: EventHub = this.events,
  ): object {
    let executor = base;
    for (const plugin of plugins) {
      if (plugin.wrapExecutor) executor = plugin.wrapExecutor(executor);
    }
    executor = recordStats(executor, recorder);
    const errorMappers = [
      ...(this.options.errors ?? []),
      ...plugins.flatMap((plugin) =>
        plugin.mapError ? [plugin.mapError] : [],
      ),
    ];
    const runner = new OperationRunner({
      meta: this.meta,
      builder: new IrBuilder(this.meta),
      executor,
      plugins,
      context,
      events,
      errorMappers,
      now: this.options.now ?? (() => new Date()),
    });

    const db: Record<string, unknown> = {
      $client: client,
      $executor: executor,
      $context: context,
      $rpc: (name: string, ...rest: unknown[]) =>
        rpc(executor, errorMappers, name, rest).map((data) => {
          const registered = this.options.rpc?.[name];
          if (registered) {
            this.events.emit('rpc', {
              name,
              invalidates: registered.invalidates,
              context,
            });
          }
          return data;
        }),
      $with: (extra: RequestContext) =>
        this.#db(client, base, { ...context, ...extra }, plugins, recorder),
      $withoutPlugins: () => this.#db(client, base, context, [], recorder),
      $stats: () => recorder.snapshot(),
      $table: (name: string) => {
        if (!Object.hasOwn(this.meta.tables, name)) {
          throw new TypeError(
            `better-supabase: unknown table "${name}". Known: ${Object.keys(this.meta.tables).join(', ')}`,
          );
        }
        return db[name];
      },
      $run: (spec: unknown, options?: { signal?: AbortSignal }) =>
        runSpec(db, spec, options?.signal),
      $many: (target: unknown, ...rest: unknown[]) => {
        if (isReadSet(target)) {
          const [values, options] = rest as [
            Readonly<Record<string, unknown>> | undefined,
            { signal?: AbortSignal } | undefined,
          ];
          return readSet(target, values, options?.signal);
        }
        const [options] = rest as [{ signal?: AbortSignal } | undefined];
        if (!Array.isArray(target)) {
          return AsyncResult.err(
            dbError(
              'invalid_request',
              'db.$many() expects an array of specs or a read set',
            ),
          );
        }
        return many(target, options?.signal, true);
      },
    };

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
              'invalid_request',
              `db.$many() entry ${invalid} is not a QuerySpec from sb.spec`,
            ),
          );
        }
        const active = usePlugins ? plugins : [];
        const batch = base.batch?.bind(base);
        const batching =
          batch && specs.length > 1
            ? batchingExecutor({ ...base, batch }, specs.length)
            : undefined;
        const target = (
          batching
            ? this.#db(client, batching.executor, context, active, recorder)
            : usePlugins
              ? db
              : this.#db(client, base, context, [], recorder)
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
              'invalid_request',
              `db.$many(${set.name}): ${problems.join(', ')}`,
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
            schema: 'public',
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
      for (const name of ['$rpc', '$run', '$many']) {
        db[name] = mapThrows(db[name] as AnyMethod, throwAs);
      }
    }
    for (const [key, table] of Object.entries(this.meta.tables)) {
      let repository: Record<string, unknown> | undefined;
      Object.defineProperty(db, key, {
        enumerable: true,
        get: () => {
          if (!repository) {
            repository = this.#repository(runner, key, table, plugins);
            if (throwAs) {
              for (const [name, method] of Object.entries(repository)) {
                if (typeof method === 'function' && name !== 'extend') {
                  repository[name] = mapThrows(method as AnyMethod, throwAs);
                }
              }
            }
          }
          return repository;
        },
      });
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
            'unexpected',
            `${set.functionName}() returned no "${key}". Run \`better-supabase gen\` and migrate.`,
          ),
        );
      }
      const rows = entry.rows ?? [];
      const stub: Executor = {
        name: 'read-set',
        execute: async (op) => {
          if (op.kind === 'select' && op.single) {
            if (rows.length > 1)
              return err(
                dbError('multiple_rows', `Expected one ${op.table.key} row`),
              );
            if (rows.length === 0 && op.single === 'one')
              return err(
                dbError('not_found', `No ${op.table.key} row matched`),
              );
          }
          return ok({ rows, count: entry.count ?? null });
        },
      };
      const decoder = this.#db(
        client,
        stub,
        context,
        [],
        new StatsRecorder(),
        new EventHub(this.events.logger),
      ) as Record<string, unknown>;
      const result = await runSpec(decoder, spec, undefined);
      if (!result.ok) return result;
      out[key] = result.data;
    }
    return ok(out);
  }

  #repository(
    runner: OperationRunner,
    key: string,
    table: SchemaMeta['tables'][string],
    plugins: readonly AnyPlugin[],
  ): Record<string, unknown> {
    const repository = createRepository(runner, table);
    for (const plugin of plugins) {
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
    repository.extend = (
      build: (base: Record<string, unknown>) => Record<string, unknown>,
    ) => ({
      ...repository,
      ...build(repository),
    });
    return repository;
  }
}

type AnyMethod = (...args: unknown[]) => unknown;

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
      dbError('invalid_request', 'db.$run() expects a QuerySpec from sb.spec'),
    );
  }
  const repository = db[spec.table] as
    | Record<string, (...args: unknown[]) => AsyncResult<unknown>>
    | undefined;
  const method = repository?.[spec.method];
  if (!method) {
    return AsyncResult.err(
      dbError('invalid_request', `Unknown table "${spec.table}" in QuerySpec`),
    );
  }
  if (containsPlaceholder(spec.args)) {
    return AsyncResult.err(
      dbError(
        'invalid_request',
        'This spec comes from a read set and still holds placeholders; run it with db.$many(readSet, params)',
      ),
    );
  }
  const args = [...spec.args];
  if (signal) {
    const index = spec.method === 'findById' ? 1 : 0;
    args[index] = { ...(args[index] as object | undefined), signal };
  }
  return method(...args);
}

function rpc(
  executor: Executor,
  errorMappers: readonly ErrorMapper[],
  name: string,
  rest: unknown[],
): AsyncResult<unknown> {
  const [args, options] = rest as [
    Readonly<Record<string, unknown>> | undefined,
    (
      | { signal?: AbortSignal; returns?: StandardSchemaV1; schema?: string }
      | undefined
    ),
  ];
  return AsyncResult.from(async () => {
    if (!executor.rpc) {
      return err<DbError>(
        dbError(
          'invalid_request',
          `Executor "${executor.name}" does not support rpc()`,
        ),
      );
    }
    const context = {
      schema: options?.schema ?? 'public',
      errorMappers,
      ...(options?.signal ? { signal: options.signal } : {}),
    };
    const result = await executor.rpc(name, args ?? {}, context);
    if (!result.ok || !options?.returns) return result;
    const checked = await validate(
      options.returns,
      result.data,
      `${name}() result`,
    );
    return checked.ok ? ok(checked.data) : checked;
  });
}

/**
 * Creates the data-layer definition from the generated `schema`.
 *
 * ```ts
 * export const sb = defineSupabase(schema).use(timestamps()).use(softDelete());
 * ```
 */
export function defineSupabase<M extends AnyModels, D, F extends AnyFunctions>(
  schema: Schema<M, D, F>,
  options?: DefineSupabaseOptions,
): BetterSupabase<M, D, F> {
  return new BetterSupabase(schema, [], options);
}
