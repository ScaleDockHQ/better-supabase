import type { MutationOp, Operation } from "../ir/types.ts";
import type { AnyModels, SchemaMeta, TableMeta } from "../schema/types.ts";
import type { ErrorMapper } from "./errors.ts";
import type { Executor } from "./executor.ts";

/** Who is making the request. */
export interface Actor {
  readonly id: string;
  readonly kind: "user" | "service" | "anon";
  readonly role?: string;
  readonly email?: string;
  /** The admin acting as this user (the `act` claim's `sub`). */
  readonly impersonator?: string;
}

/**
 * Per-connection context. Server adapters fill it from the verified JWT;
 * plugins read it (`tenant()` reads `tenant`, `actor()` reads `actor`).
 */
export interface RequestContext {
  readonly actor?: Actor;
  readonly tenant?: string;
  readonly claims?: Readonly<Record<string, unknown>>;
  readonly [key: string]: unknown;
}

/** Plugin-specific per-call options (`withDeleted`, `hard`, ...). */
export type CallOptions = Readonly<Record<string, unknown>>;

export interface HookArgs {
  readonly table: TableMeta;
  readonly schema: SchemaMeta;
  readonly context: RequestContext;
  readonly options: CallOptions;
  readonly now: () => Temporal.Instant;
}

export type MutationKind = "insert" | "upsert" | "update" | "delete";

export interface MutationEvent {
  readonly table: TableMeta;
  readonly kind: MutationKind;
  /** App-cased rows returned by the mutation. */
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  readonly context: RequestContext;
}

/** Runtime handle passed to `Plugin.repository`. */
export interface RepositoryApi {
  readonly table: TableMeta;
  readonly base: Readonly<Record<string, (...args: never[]) => unknown>>;
}

/**
 * Type-level repository extension, applied per table. Implement it as an
 * interface that reads `this['M']` and `this['T']`:
 *
 * ```ts
 * interface RestoreExtension extends RepositoryExtension {
 *   readonly methods: HasFlag<this['M'], this['T'], 'softDelete'> extends true
 *     ? { restore(id: string): AsyncResult<unknown> }
 *     : unknown;
 * }
 * ```
 */
export interface RepositoryExtension {
  readonly M: AnyModels;
  readonly T: string;
  readonly methods: unknown;
  readonly findArgs: unknown;
  readonly deleteArgs: unknown;
}

/**
 * Applies the extensions in `E` to table `T`. `E` is a tuple of extensions (as
 * built by `use()`) or a single extension. Each is applied on its own because
 * indexing an intersection of `this`-typed interfaces overflows TS < 7.
 */
/** Default extension of plugins that add no repository types. */
export interface NoExtension extends RepositoryExtension {
  readonly "~none": true;
}

export type ApplyExtension<
  E,
  M extends AnyModels,
  T extends keyof M,
  K extends "methods" | "findArgs" | "deleteArgs",
> = E extends readonly [infer Head, ...infer Rest]
  ? ApplyOne<Head, M, T, K> & ApplyExtension<Rest, M, T, K>
  : ApplyOne<E, M, T, K>;

type ApplyOne<
  E,
  M extends AnyModels,
  T extends keyof M,
  K extends "methods" | "findArgs" | "deleteArgs",
> = E extends RepositoryExtension
  ? (E & { readonly M: M; readonly T: T })[K]
  : unknown;

/** True when table `T` has the flag set by codegen. */
export type HasFlag<M, T, F extends string> = M extends AnyModels
  ? T extends keyof M
    ? M[T]["Flags"] extends { readonly [K in F]: unknown }
      ? true
      : false
    : false
  : false;

export const PLUGIN_API_VERSION = 1;

/**
 * Plugin API v1. Every hook is optional. Hooks run in `use()` order.
 */
export interface Plugin<
  Name extends string = string,
  Ext extends RepositoryExtension = NoExtension,
> {
  readonly apiVersion: 1;
  readonly name: Name;
  /**
   * Hook order: `pre` plugins run first, `post` plugins last, the rest in
   * `use()` order. Validation is `post` so it sees columns other plugins fill.
   */
  readonly enforce?: "pre" | "post";
  /** `ir`: rewrite an operation before it runs (filters, defaults). */
  readonly transformQuery?: (op: Operation, args: HookArgs) => Operation;
  /** `mutation`: rewrite a mutation or reject it by throwing a `DbException`. */
  readonly beforeMutation?: (
    op: MutationOp,
    args: HookArgs,
  ) => MutationOp | Promise<MutationOp>;
  /** `mutation`: observe a finished mutation. Cannot change the result. */
  readonly afterMutation?: (event: MutationEvent) => void | Promise<void>;
  /** `execute`: wrap the executor for tracing, caching or retries. */
  readonly wrapExecutor?: (executor: Executor) => Executor;
  /** `errors`: map custom SQLSTATE or hint codes to `DbError`s. */
  readonly mapError?: ErrorMapper;
  /** `repository`: add methods to the repositories of matching tables. */
  readonly repository?: (
    api: RepositoryApi,
  ) => Readonly<Record<string, (...args: never[]) => unknown>> | undefined;
  /** Phantom carrying the repository extension type. */
  readonly "~ext"?: Ext;
}

// oxlint-disable-next-line typescript/no-explicit-any -- the extension type is invariant, so `unknown` would reject typed plugins
export type AnyPlugin = Plugin<string, any>;

/** The plugin's repository extension; `unknown` for plugins that add none. */
export type ExtensionOf<P> =
  P extends Plugin<string, infer E>
    ? E extends NoExtension
      ? unknown
      : E
    : never;

/** `E` with extension `X` appended, as a tuple. */
export type WithExtension<E, X> = unknown extends X
  ? E
  : E extends readonly unknown[]
    ? readonly [...E, X]
    : unknown extends E
      ? readonly [X]
      : readonly [E, X];

const RANK = { pre: 0, normal: 1, post: 2 } as const;

/** Plugins in hook order: `pre`, then unmarked in `use()` order, then `post`. */
export function orderPlugins(plugins: readonly AnyPlugin[]): AnyPlugin[] {
  return plugins
    .map((plugin, index) => ({ plugin, index }))
    .sort(
      (a, b) =>
        RANK[a.plugin.enforce ?? "normal"] -
          RANK[b.plugin.enforce ?? "normal"] || a.index - b.index,
    )
    .map(({ plugin }) => plugin);
}

/** Identity helper that fixes `apiVersion` and infers the plugin types. */
export function definePlugin<
  const Name extends string,
  Ext extends RepositoryExtension = NoExtension,
>(
  plugin: Omit<Plugin<Name, Ext>, "apiVersion"> & { readonly apiVersion?: 1 },
): Plugin<Name, Ext> {
  return { ...plugin, apiVersion: 1 };
}
