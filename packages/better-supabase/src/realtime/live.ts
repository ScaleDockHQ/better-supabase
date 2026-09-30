import {
  type RealtimeChannel,
  REALTIME_SUBSCRIBE_STATES,
} from "@supabase/supabase-js";

import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { RealtimeClient, SubscriptionStatus } from "./index.ts";

/** What `liveQuery` needs from `sb`: metadata and the tables a spec reads. */
export interface LiveSource {
  readonly meta: SchemaMeta;
  tablesOf(spec: QuerySpec): string[];
}

export interface LiveQueryOptions {
  /** Called once per burst of changes, with the app keys of the tables that changed. */
  readonly onChange: (tables: readonly string[]) => void;
  /** Tenant value for tables scoped by a tenant column (`realtime-tables` topics). */
  readonly tenant?: string;
  /** Waits this long after the last change before calling `onChange`. Defaults to 100 ms. */
  readonly debounceMs?: number;
  readonly onStatus?: (status: SubscriptionStatus, error?: Error) => void;
}

export interface LiveSubscription extends Disposable, AsyncDisposable {
  /** App keys of the watched tables. */
  readonly tables: readonly string[];
  /** Tables the query reads that don't broadcast changes (not in `realtime.tables`). */
  readonly unwatched: readonly string[];
  readonly ready: Promise<void>;
  unsubscribe(): Promise<void>;
}

/**
 * A count from the server plus the spec to keep it live on the client:
 * `next.liveCount(spec)` makes one, `useLiveCount(seed)` reads it. `count`
 * is `null` when the server read failed; the client then fetches it.
 */
export interface LiveCountSeed<T extends string = string> {
  readonly spec: QuerySpec<T, "count", number>;
  readonly count: number | null;
}

/** Topic a `realtime-tables` trigger broadcasts on: `bs:t:<schema>.<table>[:<tenant>]`. */
export function liveTopic(
  meta: SchemaMeta,
  table: string,
  tenant?: string,
): string {
  const found = meta.tables[table];
  if (!found) throw new TypeError(`better-supabase: unknown table "${table}"`);
  const base = `bs:t:${found.schema}.${found.name}`;
  if (!meta.realtime?.[table]?.tenant) return base;
  if (tenant === undefined) {
    throw new TypeError(
      `better-supabase: "${table}" broadcasts per tenant; pass \`tenant\` to watch it`,
    );
  }
  return `${base}:${tenant}`;
}

interface SharedChannel {
  readonly channel: RealtimeChannel;
  readonly listeners: Set<() => void>;
  readonly ready: Promise<void>;
}

const channels = new WeakMap<RealtimeClient, Map<string, SharedChannel>>();

function join(
  client: RealtimeClient,
  topic: string,
  listener: () => void,
): { ready: Promise<void>; leave: () => Promise<void> } {
  let byTopic = channels.get(client);
  if (!byTopic) {
    byTopic = new Map();
    channels.set(client, byTopic);
  }
  let shared = byTopic.get(topic);
  if (!shared) {
    const channel = client.channel(topic, { config: { private: true } });
    const listeners = new Set<() => void>();
    channel.on("broadcast", { event: "change" }, () => {
      for (const notify of listeners) notify();
    });
    let joined = false;
    const ready = (async () => {
      await client.realtime.setAuth();
      await new Promise<void>((resolve, reject) => {
        channel.subscribe((status, error) => {
          switch (status) {
            case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
              // Broadcasts sent while disconnected are lost: a rejoin counts as a change.
              if (joined) for (const notify of listeners) notify();
              joined = true;
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CLOSED:
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
            case REALTIME_SUBSCRIBE_STATES.TIMED_OUT:
              reject(
                error ??
                  new Error(`Realtime ${status.toLowerCase()} on ${topic}`),
              );
              return;
            default: {
              const unknown: never = status;
              reject(new Error(`Unknown realtime status ${String(unknown)}`));
            }
          }
        });
      });
    })();
    ready.catch(() => undefined);
    shared = { channel, listeners, ready };
    byTopic.set(topic, shared);
  }
  const current = shared;
  current.listeners.add(listener);
  let left = false;
  return {
    ready: current.ready,
    leave: async () => {
      if (left) return;
      left = true;
      current.listeners.delete(listener);
      if (current.listeners.size > 0) return;
      byTopic.delete(topic);
      await client.removeChannel(current.channel);
    },
  };
}

/**
 * Calls `onChange` when a table the spec reads changes, so you can refetch.
 * Needs the `realtime-tables` SQL module and the tables in
 * `realtime.tables`. Live queries on the same client share one channel per
 * table, so any number of them can run at once.
 *
 * ```ts
 * using live = liveQuery(sb, supabase, spec, { onChange: () => refetch() });
 * ```
 */
export function liveQuery(
  sb: LiveSource,
  client: RealtimeClient,
  spec: QuerySpec | readonly string[],
  options: LiveQueryOptions,
): LiveSubscription {
  const touched = Array.isArray(spec)
    ? (spec as readonly string[])
    : sb.tablesOf(spec as QuerySpec);
  const tables = touched.filter((table) => sb.meta.realtime?.[table]);
  const unwatched = touched.filter((table) => !sb.meta.realtime?.[table]);
  const debounceMs = options.debounceMs ?? 100;
  const changed = new Set<string>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let closed = false;

  const flush = (): void => {
    timer = undefined;
    if (closed || changed.size === 0) return;
    const batch = [...changed];
    changed.clear();
    options.onChange(batch);
  };

  const memberships = tables.map((table) =>
    join(client, liveTopic(sb.meta, table, options.tenant), () => {
      changed.add(table);
      if (timer !== undefined) clearTimeout(timer);
      timer = setTimeout(flush, debounceMs);
    }),
  );

  options.onStatus?.(tables.length === 0 ? "closed" : "joining");
  const ready = Promise.all(memberships.map((member) => member.ready)).then(
    () => {
      if (!closed && tables.length > 0) options.onStatus?.("subscribed");
    },
    (cause: unknown) => {
      const error = cause instanceof Error ? cause : new Error(String(cause));
      options.onStatus?.("error", error);
      throw error;
    },
  );
  ready.catch(() => undefined);

  const unsubscribe = async (): Promise<void> => {
    if (closed) return;
    closed = true;
    if (timer !== undefined) clearTimeout(timer);
    await Promise.all(memberships.map((member) => member.leave()));
    options.onStatus?.("closed");
  };

  return {
    tables,
    unwatched,
    ready,
    unsubscribe,
    [Symbol.dispose]: () => void unsubscribe(),
    [Symbol.asyncDispose]: unsubscribe,
  };
}

/** What `liveCount` runs the spec with: a `db` from `sb.connect()` or `createBrowser()`. */
export interface CountRunner {
  $run(spec: QuerySpec): PromiseLike<Result<unknown>>;
}

export interface LiveCountOptions extends Omit<LiveQueryOptions, "onChange"> {
  readonly onCount: (count: number) => void;
  /** A failed refetch; the previous count stays valid. */
  readonly onError?: (error: DbError) => void;
  /** Count right away. Defaults to `true`; pass `false` when you have a seed. */
  readonly immediate?: boolean;
}

/**
 * Keeps a count current: runs the `count` spec (a HEAD request) now, after
 * each debounced change to a table it reads, and after the channel rejoins.
 * Responses that arrive out of order are dropped.
 *
 * ```ts
 * using live = liveCount(sb, supabase, db, sb.spec.notes.count(), {
 *   onCount: (count) => render(count),
 * });
 * ```
 */
export function liveCount(
  sb: LiveSource,
  client: RealtimeClient,
  db: CountRunner,
  spec: QuerySpec<string, "count", number>,
  options: LiveCountOptions,
): LiveSubscription {
  let latest = 0;
  let closed = false;
  const refetch = (): void => {
    const call = ++latest;
    void Promise.resolve(db.$run(spec)).then((result) => {
      if (closed || call !== latest) return;
      if (result.ok) options.onCount(result.data as number);
      else options.onError?.(result.error);
    });
  };
  const live = liveQuery(sb, client, spec, {
    onChange: refetch,
    ...(options.tenant === undefined ? {} : { tenant: options.tenant }),
    ...(options.debounceMs === undefined
      ? {}
      : { debounceMs: options.debounceMs }),
    ...(options.onStatus ? { onStatus: options.onStatus } : {}),
  });
  if (options.immediate ?? true) refetch();
  const unsubscribe = async (): Promise<void> => {
    closed = true;
    await live.unsubscribe();
  };
  return {
    ...live,
    unsubscribe,
    [Symbol.dispose]: () => void unsubscribe(),
    [Symbol.asyncDispose]: unsubscribe,
  };
}
