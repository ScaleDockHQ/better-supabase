import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { CacheAdapter } from "../core/cache.ts";
import type { EventHub } from "../core/events.ts";
import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
  RpcContext,
} from "../core/executor.ts";
import type { KeptCache, KeptStore } from "../core/kept-cache.ts";
import type { Result } from "../core/result.ts";
import type { CacheEntryStat } from "../core/stats.ts";
import type { Operation } from "../ir/types.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { BootstrapMemo, BootstrapRow } from "../server/bootstrap.ts";
import type { TenantShare } from "../server/tenant-share.ts";
import type {
  CacheScope,
  CachedOptions,
  KeepReadsOptions,
  KeptFunction,
  KeptOptions,
  NextKeptOptions,
  SessionHandle,
} from "./types.ts";

import { snapshotOf } from "../auth/snapshot.ts";
import { canonicalJson } from "../core/canonical-json.ts";
import {
  createKeptCache,
  keptKey,
  keptVersionOf,
  memoryKeptStore,
} from "../core/kept-cache.ts";
import { rpcFunction } from "../core/rpc-result.ts";
import { cacheTagsOf } from "../core/tags.ts";
import {
  sharedFunctionsOf,
  sharedReader,
  tablesWithFunctions,
} from "../server/tenant-share.ts";
import { withReadSetTables } from "./action-bound.ts";
import { tableTags } from "./cache.ts";
import { applyCacheEntry } from "./entry.ts";
import { cacheKeyOf } from "./session-handle.ts";

const DEFAULT_REVALIDATE = 300;
const DEFAULT_EXPIRE = 86_400;

/**
 * A function call that must not be stored. Thrown from the fill so the kept
 * store never writes the envelope, then caught and returned as the result.
 */
class UnkeptRpc extends Error {
  readonly result: Result<unknown>;

  constructor(result: Result<unknown>) {
    super("kept rpc");
    this.name = "UnkeptRpc";
    this.result = result;
  }
}

function schemaOf(value: unknown): SchemaMeta | undefined {
  if (
    typeof value === "object" &&
    value !== null &&
    "functions" in value &&
    "tables" in value
  ) {
    // SAFETY: createNext passes the definition's SchemaMeta as deps.meta.
    return value as SchemaMeta;
  }

  return undefined;
}

/**
 * A function call is kept when the caller named the tables it reads, unless the
 * schema says the function is volatile. A function the schema doesn't name (a
 * block call, an API function) is kept: the tables are the expiry.
 */
function keepsRpc(
  context: RpcContext,
  tables: readonly string[] | undefined,
  meta: SchemaMeta | undefined,
  name: string,
  args: Readonly<Record<string, unknown>>,
): boolean {
  if (tables === undefined || tables.length === 0) {
    return false;
  }

  const fn =
    context.function ??
    (meta === undefined
      ? undefined
      : rpcFunction(meta, name, context.schema, args));

  if (fn?.volatility === "volatile") {
    return false;
  }

  if (
    context.get === true ||
    fn?.volatility === "stable" ||
    fn?.volatility === "immutable"
  ) {
    return true;
  }

  // The schema doesn't name it. The caller listed the tables it reads.
  return fn === undefined;
}

interface KeptScope<Ctx, C, P> {
  readonly ctx: Ctx;
  readonly view: AuthSession<C, P>;
  readonly scope: CacheScope;
  readonly tenant: string | undefined;
}

type KeptContext<C, P> = {
  readonly auth: AuthState<C, P>;
  readonly support?: { readonly session: { readonly id: string } } | null;
};

/** What `bsb.kept()` needs from `createNext`. */
export interface KeptDeps<Ctx extends KeptContext<C, P>, C, P> {
  readonly events: EventHub;
  readonly attach: (adapter: CacheAdapter) => void;
  readonly options: NextKeptOptions | undefined;
  readonly meta: unknown;
  readonly scopeOf: (
    source: SessionHandle | undefined,
    tenant: string | undefined,
  ) => Promise<KeptScope<Ctx, C, P>>;
  readonly userTags: (userId: string) => readonly string[];
  readonly waitUntil: (work: Promise<unknown>) => void;
  /** Records the store's tag calls on the current request. */
  readonly onTagCalls?: (calls: number, tags: readonly string[]) => void;
  /** Records how a call was served, on the request `source` came from. */
  readonly onEntry?: (
    record: CacheEntryStat,
    source: SessionHandle | undefined,
    /** What the call returned, for its size. */
    value: unknown,
  ) => void;
  /** The `anon` context a `share: "public"` entry fills with. */
  readonly publicScope: () => KeptScope<Ctx, C, P>;
  /** How a `share: "tenant"` entry of `ctx` that reads `tables` is keyed. */
  readonly tenantShare: (
    ctx: Ctx,
    tables: readonly string[],
    tenant: string | undefined,
    functions?: readonly string[],
  ) => Promise<TenantShare>;
}

export interface KeptBinding<Ctx, C = unknown, P = unknown> {
  readonly kept: <A extends readonly unknown[], R>(
    fn: (ctx: Ctx, ...args: A) => Promise<R>,
    options: KeptOptions<string, A>,
  ) => KeptFunction<A, R>;
  /**
   * The wrapper `bsb.cached({ keep })` puts around a client's executor: its
   * reads go through the kept store, keyed on the user and the operation.
   */
  readonly keepReads: (
    scope: KeptScope<Ctx, C, P>,
    keep: KeepReadsOptions,
  ) => (executor: Executor) => Executor;
  /**
   * `memo` with each answer kept for `bootstrap({ kept })`; `memo` itself for a
   * call without it, a support session or a token that failed to verify.
   */
  readonly keepMemo: (
    scope: KeptScope<Ctx, C, P>,
    call: {
      readonly rpc: string;
      readonly kept?: BootstrapOptionsKept | undefined;
      readonly tables?: readonly string[] | undefined;
    },
    memo: BootstrapMemo,
  ) => BootstrapMemo;
  /** `ctx.db` of a `bsb.cached({ keep })` scope, with its reads kept. */
  readonly keepDb: <
    Db extends { $wrapExecutor: (wrap: (e: Executor) => Executor) => Db },
  >(
    scope: KeptScope<Ctx, C, P>,
    db: Db,
    options: CachedOptions,
  ) => Db;
  /**
   * Expires `tags` in the kept store, as `invalidateAll` does for Next.js. A
   * store the app named is opened for it; the default memory store only when a
   * kept function already ran. Failures are logged.
   */
  readonly expireTags: (tags: readonly string[]) => void;
  /** The same, resolving once the store has expired them; rejects on failure. */
  readonly expireTagsNow: (tags: readonly string[]) => Promise<void>;
}

/** `BootstrapOptions.kept`. */
type BootstrapOptionsKept =
  | true
  | { readonly life?: { readonly revalidate?: number } };

/** The calls a store makes for `tags`: one per batch of 16. */
const batches = (tags: readonly string[]): number =>
  Math.ceil(tags.length / 16);

/** The memory store of an app that names none, one per `betterSupabase`. */
const defaultStores = new WeakMap<EventHub, KeptStore>();

/** The kept cache of each store, so two `createNext` calls share one. */
const caches = new WeakMap<KeptStore, KeptCache>();

/** `bsb.kept()`, bound to one `createNext`. */
export function keptBinding<Ctx extends KeptContext<C, P>, C, P>(
  deps: KeptDeps<Ctx, C, P>,
): KeptBinding<Ctx, C, P> {
  let cache: KeptCache | undefined;
  let version: Promise<string> | undefined;
  // SAFETY: `createNext` passes the generated schema's meta, or nothing.
  const schemaMeta = deps.meta as SchemaMeta | undefined;
  /** Functions whose `share: "tenant"` refusal was logged. */
  const warned = new Set<string>();

  const cacheOf = (): KeptCache => {
    if (cache) {
      return cache;
    }

    const store =
      deps.options?.store ??
      defaultStores.get(deps.events) ??
      memoryKeptStore();

    defaultStores.set(deps.events, defaultStores.get(deps.events) ?? store);

    const existing = caches.get(store);

    cache =
      existing ??
      createKeptCache({
        store,
        ...(deps.options?.onSkip ? { onSkip: deps.options.onSkip } : {}),
        wait: deps.options?.wait,
        onError: (cause) => {
          deps.events.logger.warn("bsb.kept() could not reach its store", {
            cause,
          });
        },
      });

    if (!existing) {
      const attached = cache;

      caches.set(store, attached);
      deps.attach({
        name: attached.adapter.name,
        invalidate: async (target) => {
          const tags = cacheTagsOf(target);

          await attached.expireTags(tags);
          deps.onTagCalls?.(batches(tags), tags);
        },
      });
    }

    return cache;
  };

  const schemaVersion = (): Promise<string> => {
    version ??= keptVersionOf(deps.meta).catch(() => "0");

    return version;
  };

  const expireTagsNow = async (tags: readonly string[]): Promise<void> => {
    if (tags.length === 0 || (!cache && !deps.options?.store)) {
      return;
    }

    await cacheOf().expireTags(tags);
    deps.onTagCalls?.(batches(tags), tags);
  };

  const expireTags = (tags: readonly string[]): void => {
    expireTagsNow(tags).catch((cause: unknown) => {
      deps.events.logger.warn("bsb.kept() could not expire its tags", {
        cause,
      });
    });
  };

  const build = <A extends readonly unknown[], R>(
    fn: (ctx: Ctx, ...args: A) => Promise<R>,
    options: KeptOptions<string, A>,
  ): KeptFunction<A, R> & {
    in(resolved: KeptScope<Ctx, C, P>, ...args: A): Promise<R>;
  } => {
    const revalidate = options.life?.revalidate ?? DEFAULT_REVALIDATE;
    const expire = Math.max(options.life?.expire ?? DEFAULT_EXPIRE, revalidate);

    const run = async (
      source: SessionHandle | undefined,
      args: A,
      resolved?: KeptScope<Ctx, C, P>,
    ): Promise<R> => {
      const open = options.share === "public";

      // A public entry never reads the request, so it runs in a plain
      // "use cache" scope too.
      const { ctx, view, scope, tenant } =
        resolved ??
        (open
          ? deps.publicScope()
          : await deps.scopeOf(source, options.tenant?.(...args)));

      const appTags =
        typeof options.tags === "function"
          ? options.tags(...args)
          : (options.tags ?? []);

      const declared = tablesWithFunctions(
        schemaMeta,
        options.tables ?? [],
        options.functions,
      );

      const entry = withReadSetTables({
        ...(declared.length > 0 ? { tables: declared } : {}),
        ...(options.readSet ? { readSet: options.readSet } : {}),
        tags: appTags,
        life: { stale: revalidate, revalidate, expire },
      });

      try {
        applyCacheEntry({
          ctx,
          view,
          scope,
          tenant,
          entry,
          userTags: deps.userTags,
          warn: undefined,
        });
      } catch {
        // Outside a "use cache" scope `cacheLife` throws: there is no entry
        // to apply the tags to.
      }

      // A support session reads with restrictions a shared entry can't carry,
      // and a failed auth must reach the function to report it.
      if (ctx.support || ctx.auth.kind === "invalid") {
        return fn(ctx, ...args);
      }

      const tables = entry.tables ?? [];

      const decided: TenantShare =
        options.share === "tenant"
          ? await deps.tenantShare(ctx, tables, tenant, options.functions)
          : { kind: "user" };

      const shared = open
        ? "public"
        : decided.kind === "shared"
          ? decided.key
          : undefined;

      const share = canonicalJson(
        await cacheKeyOf({
          userId: view.kind === "user" ? view.user.id : null,
          tenant,
          support: null,
          snapshot: snapshotOf(ctx.auth),
          // `version` carries the schema hash.
          meta: undefined,
          share:
            shared === undefined
              ? "user"
              : { key: () => (open ? "public" : `tenant:${shared}`) },
        }),
      );

      const key = await keptKey({
        name: options.name,
        args,
        share,
        version: options.version ?? (await schemaVersion()),
      });

      if (decided.kind === "refused") {
        if (!warned.has(options.name)) {
          warned.add(options.name);
          deps.events.logger.warn(
            `bsb.kept("${options.name}") keeps its entries per user: ${decided.error.message}`,
            { error: decided.error },
          );
        }

        deps.options?.onSkip?.({
          name: options.name,
          key,
          reason: "share",
          detail: decided.error.message,
        });
      }

      const reader =
        shared === undefined
          ? undefined
          : sharedReader(
              ctx,
              tables,
              sharedFunctionsOf(schemaMeta, options.functions),
            );

      const tags = [
        ...(view.kind === "user" && shared === undefined
          ? deps.userTags(view.user.id)
          : []),
        ...appTags,
        ...tables.flatMap((table) =>
          tableTags(table, tenant === undefined ? {} : { tenant }),
        ),
      ];

      const served = await cacheOf().serve({
        name: options.name,
        key,
        tags,
        revalidate,
        expire,
        fill: () => fn(reader?.ctx ?? ctx, ...args),
        refuse: reader ? () => reader.guard.refused()?.message : undefined,
        background: deps.waitUntil,
      });

      deps.onEntry?.(
        {
          id: options.name,
          kind: "kept",
          outcome: served.outcome,
          ...(served.fillMs === undefined ? {} : { fillMs: served.fillMs }),
        },
        source,
        served.value,
      );

      return served.value;
    };

    return Object.assign((...args: A) => run(undefined, args), {
      as:
        (source: SessionHandle) =>
        (...args: A) =>
          run(source, args),
      in: (resolved: KeptScope<Ctx, C, P>, ...args: A) =>
        run(undefined, args, resolved),
    });
  };

  const kept = <A extends readonly unknown[], R>(
    fn: (ctx: Ctx, ...args: A) => Promise<R>,
    options: KeptOptions<string, A>,
  ): KeptFunction<A, R> => build(fn, options);

  const keepReads =
    (
      scope: KeptScope<Ctx, C, P>,
      keep: KeepReadsOptions,
    ): ((executor: Executor) => Executor) =>
    (inner) => {
      const read = (
        op: Operation,
        context: ExecuteContext,
      ): Promise<Result<ExecuteResult>> => {
        // A function source, or an operation JSON can't carry, is not kept.
        let canonical: string;

        if (op.kind !== "select" || op.source !== undefined) {
          return inner.execute(op, context);
        }

        try {
          canonical = canonicalJson({ ...op, table: op.table.key });
        } catch {
          return inner.execute(op, context);
        }

        const table = op.table.key;

        const fn = build(
          (_ctx: Ctx, _operation: string) => inner.execute(op, context),
          {
            name: `${keep.name}:${table}`,
            tables: [table],
            ...(keep.life ? { life: keep.life } : {}),
            ...(keep.version === undefined ? {} : { version: keep.version }),
          },
        );

        return fn.in(scope, canonical);
      };

      const call = inner.rpc?.bind(inner);
      const meta = schemaOf(deps.meta);

      if (call === undefined) {
        return { ...inner, execute: read };
      }

      const rpc = (
        name: string,
        args: Readonly<Record<string, unknown>>,
        context: RpcContext,
      ): Promise<Result<unknown>> => {
        const tables = keep.tables;

        if (
          tables === undefined ||
          !keepsRpc(context, tables, meta, name, args)
        ) {
          return call(name, args, context);
        }

        let canonical: string;

        try {
          canonical = canonicalJson({ schema: context.schema, name, args });
        } catch {
          return call(name, args, context);
        }

        const fn = build(
          async (_ctx: Ctx, _key: string) => {
            const result = await call(name, args, context);

            if (!result.ok) {
              throw new UnkeptRpc(result);
            }

            return result;
          },
          {
            name: `${keep.name}:rpc:${context.schema}.${name}`,
            tables,
            ...(keep.life ? { life: keep.life } : {}),
            ...(keep.version === undefined ? {} : { version: keep.version }),
          },
        );

        return fn.in(scope, canonical).catch((error: unknown) => {
          if (error instanceof UnkeptRpc) {
            return error.result;
          }

          throw error;
        });
      };

      return { ...inner, execute: read, rpc };
    };

  const keepMemo = (
    scope: KeptScope<Ctx, C, P>,
    call: {
      readonly rpc: string;
      readonly kept?: BootstrapOptionsKept | undefined;
      readonly tables?: readonly string[] | undefined;
    },
    memo: BootstrapMemo,
  ): BootstrapMemo => {
    const keep = call.kept;

    if (!keep || scope.ctx.support || scope.ctx.auth.kind === "invalid") {
      return memo;
    }

    const revalidate =
      (keep === true ? undefined : keep.life?.revalidate) ?? 30;

    return Object.assign(
      (key: string, run: () => Promise<BootstrapRow>) =>
        memo(key, () =>
          build((_ctx: Ctx, _key: string) => run(), {
            name: `bootstrap:${call.rpc}`,
            tables: [
              ...new Set([
                ...(call.tables ?? []),
                ...(schemaMeta?.bootstrap?.tables?.[call.rpc] ?? []),
              ]),
            ],
            life: { revalidate },
          }).in(scope, key),
        ),
      memo.has ? { has: memo.has } : {},
    );
  };

  const keepDb = <
    Db extends { $wrapExecutor: (wrap: (e: Executor) => Executor) => Db },
  >(
    scope: KeptScope<Ctx, C, P>,
    db: Db,
    options: CachedOptions,
  ): Db => {
    const keep = "keep" in options ? options.keep : undefined;

    return !keep || scope.ctx.support || scope.ctx.auth.kind === "invalid"
      ? db
      : db.$wrapExecutor(keepReads(scope, keep));
  };

  return { kept, keepReads, keepDb, keepMemo, expireTags, expireTagsNow };
}
