import type {
  AnyFunctions,
  AnyModels,
  Schema,
  SchemaMeta,
  TableKey,
} from "../schema/types.ts";
import type { CacheAdapter, CacheTarget } from "./cache.ts";
import type { BlockSetClients, DbBlockSource, WithExtra } from "./db-blocks.ts";
import type { BucketRegistry } from "./db-buckets.ts";
import type { ConnectOptions, SupabaseOptions } from "./define-types.ts";
import type { DbError } from "./errors.ts";
import type { EventHandler, EventHub, EventName } from "./events.ts";
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
import type { Db } from "./repository-types.ts";
import type { QuerySpec, Specs } from "./spec.ts";
import type { StandardSchemaV1 } from "./standard.ts";

import { cacheTargetOf, rpcCacheTargets } from "./cache.ts";
import { definitionEvents } from "./diagnostics.ts";
import { orderPlugins } from "./plugin.ts";
import { createSpecs, specTables } from "./spec.ts";
import {
  optionalTemporal,
  provideTemporal,
  providedTemporal,
} from "./temporal.ts";

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
          "createSupabase got a different `temporal` namespace than the one already provided; decoded rows, jobs and webhooks in this process now use the newer one. Pass the same namespace to every definition.",
        );
      }

      provideTemporal(temporal);
    }
  }

  get meta(): SchemaMeta {
    return this.schema.meta;
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

  /**
   * The schema set by `userMetadata()`; its output types
   * `session.userMetadata`.
   */
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
   * const betterSupabase = createSupabase(schema).claims(
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
   * into a typed `session.userMetadata`. Users can change their metadata with
   * `auth.updateUser()`, so a failure only leaves `profile` undefined (with one
   * warning), and no authorization code reads it. It is for display only:
   * roles, memberships, the tenant and entitlements come from the verified
   * claims, never from `profile`.
   *
   * ```ts
   * const betterSupabase = createSupabase(schema).userMetadata(
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
   * const betterSupabase = createSupabase(schema).mapError(
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
   * const betterSupabase = createSupabase(schema).buckets({ logos, avatars });
   * betterSupabase.connect(client).$buckets.logos.signedUrl({ ... });
   * ```
   */
  buckets<const R extends BucketRegistry>(
    registered: R,
  ): BetterSupabase<M, D, F, E, C, P, WithExtra<B, "buckets", R>> {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, buckets: registered },
      this.events,
    );
  }

  /**
   * Returns a new instance whose every `Db` has the installed block instances
   * as properties, under their keys in camel case. Each client runs as the
   * `Db`'s caller and acts in its organization (`db.$context.tenant`), so app
   * code passes neither a transport nor an organization.
   *
   * ```ts
   * export const betterSupabase = createSupabase(schema).blocks(
   *   defineBlocks(blockConfig, blocks),
   * );
   * const db = await bsb.db();
   * await db.tags.list({ kind: "customer" });
   * ```
   */
  blocks<const S extends DbBlockSource>(
    set: S,
  ): BetterSupabase<
    M,
    D,
    F,
    E,
    C,
    P,
    WithExtra<B, "blocks", BlockSetClients<S>>
  > {
    return new BetterSupabase(
      this.schema,
      this.plugins,
      { ...this.options, blocks: set },
      this.events,
    );
  }

  #specs: Specs<M, E> | undefined;

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
   * request context. Cheap: call it once per request. Needs the connection
   * runtime, which `better-supabase/client`, the server and the adapters
   * install.
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
    return connectionRuntime().connect(this, source, context, options);
  }

  /**
   * The `postgrestExecutor` options this definition implies (`urlLengthLimit`,
   * `postgrestVersion`), for adapters that build their own executor and should
   * chunk reads the same way.
   */
  executorOptions(): PostgrestExecutorOptions {
    const { urlLengthLimit, postgrestVersion } = this.options;

    return {
      maxRows: this.options.maxRows ?? 1000,
      ...(urlLengthLimit === undefined ? {} : { urlLengthLimit }),
      ...(postgrestVersion === undefined ? {} : { postgrestVersion }),
    };
  }

  /**
   * Adds a table to a definition whose schema sets `lazyTables`, so a `db` made
   * earlier reads it too. The split layout's browser client calls it through
   * `client.table(customers)`; everything else lists its tables.
   */
  registerTable(table: SchemaMeta["tables"][string]): void {
    connectionRuntime().registerTable(this, table);
  }
}

/** The part of a definition the connection runtime reads. */
export type Definition = Pick<
  BetterSupabase,
  "schema" | "plugins" | "events" | "options" | "meta" | "executorOptions"
>;

/** What turns a definition into a `db`; installed by the entries that connect. */
export interface ConnectionRuntime {
  connect(
    definition: Definition,
    source: PostgrestClientLike | Executor,
    context: RequestContext,
    options: ConnectOptions,
  ): unknown;
  registerTable(
    definition: Definition,
    table: SchemaMeta["tables"][string],
  ): void;
}

let installed: ConnectionRuntime | undefined;

/** Installs the connection runtime. Entries that connect call it once. */
export function installConnectionRuntime(runtime: ConnectionRuntime): void {
  installed = runtime;
}

function connectionRuntime(): ConnectionRuntime {
  if (!installed) {
    throw new TypeError(
      "better-supabase: connect() needs the connection runtime. Create the client or server (better-supabase/client, better-supabase/server or an adapter) before calling definition.connect().",
    );
  }

  return installed;
}

/**
 * Creates the data-layer definition from the generated `schema`, with the
 * repository extensions of the installed blocks (organization scope, trash,
 * `created_by` and `updated_at` stamps, write validation) already in place.
 *
 * ```ts
 * export const betterSupabase = createSupabase(schema).use(guards());
 * ```
 */
export function createSupabase<
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
