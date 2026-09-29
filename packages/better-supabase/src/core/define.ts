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
import { createRepository, OperationRunner } from './repository.ts';
import { AsyncResult, err, ok } from './result.ts';
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
  ): BetterSupabase<M, D, F, WithExtension<E, ExtensionOf<P>>> {
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
  ): BetterSupabase<M, D, F, E> {
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
      events: this.events,
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
    };

    for (const [key, table] of Object.entries(this.meta.tables)) {
      let repository: Record<string, unknown> | undefined;
      Object.defineProperty(db, key, {
        enumerable: true,
        get: () => {
          repository ??= this.#repository(runner, key, table, plugins);
          return repository;
        },
      });
    }
    return db;
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
