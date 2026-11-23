import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { CacheAdapter } from "../core/cache.ts";
import type { EventHub } from "../core/events.ts";
import type { KeptCache, KeptStore } from "../core/kept-cache.ts";
import type {
  CacheScope,
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
import { cacheTagsOf } from "../core/tags.ts";
import { withReadSetTables } from "./action-bound.ts";
import { tableTags } from "./cache.ts";
import { applyCacheEntry } from "./entry.ts";
import { cacheKeyOf } from "./session-handle.ts";

const DEFAULT_REVALIDATE = 300;
const DEFAULT_EXPIRE = 86_400;

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
  readonly onTagCalls?: (calls: number) => void;
}

export interface KeptBinding<Ctx> {
  readonly kept: <A extends readonly unknown[], R>(
    fn: (ctx: Ctx, ...args: A) => Promise<R>,
    options: KeptOptions<string, A>,
  ) => KeptFunction<A, R>;
  /**
   * Expires `tags` in the kept store, as `invalidateAll` does for Next.js. A
   * store the app named is opened for it; the default memory store only when a
   * kept function already ran. Failures are logged.
   */
  readonly expireTags: (tags: readonly string[]) => void;
}

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
): KeptBinding<Ctx> {
  let cache: KeptCache | undefined;
  let version: Promise<string> | undefined;

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
          deps.onTagCalls?.(batches(tags));
        },
      });
    }

    return cache;
  };

  const schemaVersion = (): Promise<string> => {
    version ??= keptVersionOf(deps.meta).catch(() => "0");

    return version;
  };

  const expireTags = (tags: readonly string[]): void => {
    if (tags.length === 0 || (!cache && !deps.options?.store)) {
      return;
    }

    cacheOf()
      .expireTags(tags)
      .then(() => {
        deps.onTagCalls?.(batches(tags));
      })
      .catch((cause: unknown) => {
        deps.events.logger.warn("bsb.kept() could not expire its tags", {
          cause,
        });
      });
  };

  const kept = <A extends readonly unknown[], R>(
    fn: (ctx: Ctx, ...args: A) => Promise<R>,
    options: KeptOptions<string, A>,
  ): KeptFunction<A, R> => {
    const revalidate = options.life?.revalidate ?? DEFAULT_REVALIDATE;
    const expire = Math.max(options.life?.expire ?? DEFAULT_EXPIRE, revalidate);

    const run = async (
      source: SessionHandle | undefined,
      args: A,
    ): Promise<R> => {
      const { ctx, view, scope, tenant } = await deps.scopeOf(
        source,
        options.tenant?.(...args),
      );

      const appTags =
        typeof options.tags === "function"
          ? options.tags(...args)
          : (options.tags ?? []);

      const entry = withReadSetTables({
        ...(options.tables ? { tables: options.tables } : {}),
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

      const share = canonicalJson(
        cacheKeyOf({
          userId: view.kind === "user" ? view.user.id : null,
          tenant,
          support: null,
          snapshot: snapshotOf(ctx.auth),
          share: "user",
        }),
      );

      const key = await keptKey({
        name: options.name,
        args,
        share,
        version: options.version ?? (await schemaVersion()),
      });

      const tags = [
        ...(view.kind === "user" ? deps.userTags(view.user.id) : []),
        ...appTags,
        ...(entry.tables ?? []).flatMap((table) =>
          tableTags(table, tenant === undefined ? {} : { tenant }),
        ),
      ];

      const served = await cacheOf().serve({
        name: options.name,
        key,
        tags,
        revalidate,
        expire,
        fill: () => fn(ctx, ...args),
        background: deps.waitUntil,
      });

      return served.value;
    };

    return Object.assign((...args: A) => run(undefined, args), {
      as:
        (source: SessionHandle) =>
        (...args: A) =>
          run(source, args),
    });
  };

  return { kept, expireTags };
}
