import {
  type RealtimeChannel,
  REALTIME_SUBSCRIBE_STATES,
} from "@supabase/supabase-js";

import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { RealtimeClient, SubscriptionStatus } from "./index.ts";

import { refreshRealtimeAuth } from "./auth.ts";

/** What `liveQuery` needs from `betterSupabase`: metadata and the tables a spec reads. */
export interface LiveSource {
  readonly meta: SchemaMeta;
  tablesOf(spec: QuerySpec): string[];
}

export interface LiveQueryOptions {
  /** Called once per burst of changes, with the app keys of the tables that changed. */
  readonly onChange: (tables: readonly string[]) => void;
  /** Tenant value for tables scoped by a tenant column (`realtime-tables` topics). */
  readonly tenant?: string;
  /** The signed-in user's id, for tables that broadcast per user (`realtime.users`). */
  readonly user?: string;
  /** Waits this long after the last change before calling `onChange`. Defaults to 100 ms. */
  readonly debounceMs?: number;
  /**
   * Also reports a channel that errors after it joined (`error`) and its
   * rejoin (`subscribed`), not only the first join.
   */
  readonly onStatus?: (status: SubscriptionStatus, error?: Error) => void;
  /**
   * Retries a first join that failed, after 1 s and then twice as long each
   * time, up to 30 s. Pass `false` to stay in `error`. Defaults to `true`.
   */
  readonly retry?: boolean;
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
 * `bs.liveCount(spec)` makes one, `useLiveCount(seed)` reads it. `count`
 * is `null` when the server read failed; the client then fetches it.
 */
export interface LiveCountSeed<T extends string = string> {
  readonly spec: QuerySpec<T, "count", number>;
  readonly count: number | null;
  /** When the count was taken (epoch ms). `useLiveCount` counts again after joining when it is older than a second. */
  readonly at?: number;
}

/**
 * Topic a `realtime-tables` trigger broadcasts on:
 * `bs:t:<schema>.<table>[:<tenant>]`, or `bs:t:<schema>.<table>:u:<user>`
 * for a `realtime.users` table.
 */
export function liveTopic(
  meta: SchemaMeta,
  table: string,
  tenant?: string,
  user?: string,
): string {
  const found = meta.tables[table];
  if (!found) throw new TypeError(`better-supabase: unknown table "${table}"`);
  const base = `bs:t:${found.schema}.${found.name}`;
  if (meta.realtime?.[table]?.user) {
    if (user === undefined) {
      throw new TypeError(
        `better-supabase: "${table}" broadcasts per user; pass \`user\` to watch it`,
      );
    }
    return `${base}:u:${user}`;
  }
  if (!meta.realtime?.[table]?.tenant) return base;
  if (tenant === undefined) {
    throw new TypeError(
      `better-supabase: "${table}" broadcasts per tenant; pass \`tenant\` to watch it`,
    );
  }
  return `${base}:${tenant}`;
}

type StatusListener = (status: "subscribed" | "error", error?: Error) => void;

interface SharedChannel {
  readonly channel: RealtimeChannel;
  readonly listeners: Set<() => void>;
  readonly statuses: Set<StatusListener>;
  readonly ready: Promise<void>;
}

const channels = new WeakMap<RealtimeClient, Map<string, SharedChannel>>();

function join(
  client: RealtimeClient,
  topic: string,
  listener: () => void,
  onStatus?: StatusListener,
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
    const statuses = new Set<StatusListener>();
    channel.on("broadcast", { event: "change" }, () => {
      for (const notify of listeners) notify();
    });
    let joined = false;
    const evict = (): void => {
      if (byTopic.get(topic) !== entry) return;
      byTopic.delete(topic);
      void client.removeChannel(channel);
    };
    const ready = (async () => {
      await refreshRealtimeAuth(client);
      await new Promise<void>((resolve, reject) => {
        channel.subscribe((status, error) => {
          switch (status) {
            case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
              // Broadcasts sent while disconnected are lost: a rejoin counts as a change.
              if (joined) {
                for (const notify of listeners) notify();
                for (const notify of statuses) notify("subscribed");
              }
              joined = true;
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CLOSED:
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
            case REALTIME_SUBSCRIBE_STATES.TIMED_OUT: {
              const failure =
                error ??
                new Error(`Realtime ${status.toLowerCase()} on ${topic}`);
              // Settled already once joined: listeners hear it instead.
              if (joined)
                for (const notify of statuses) notify("error", failure);
              reject(failure);
              // A joined channel rejoins on its own; one that never joined is
              // dropped so the next join opens a fresh channel. Removing it
              // reports CLOSED, so this runs after the reject.
              if (!joined) evict();
              return;
            }
            default: {
              const unknown: never = status;
              reject(new Error(`Unknown realtime status ${String(unknown)}`));
            }
          }
        });
      });
    })();
    ready.catch(() => undefined);
    const entry: SharedChannel = { channel, listeners, statuses, ready };
    shared = entry;
    byTopic.set(topic, entry);
  }
  const current = shared;
  current.listeners.add(listener);
  if (onStatus) current.statuses.add(onStatus);
  let left = false;
  return {
    ready: current.ready,
    leave: async () => {
      if (left) return;
      left = true;
      current.listeners.delete(listener);
      if (onStatus) current.statuses.delete(onStatus);
      if (current.listeners.size > 0) return;
      // A join in the same tick (React StrictMode remounts) keeps the channel:
      // removing it first would hand the new listener a closing channel.
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 0);
      });
      if (current.listeners.size > 0 || byTopic.get(topic) !== current) return;
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
 * using live = liveQuery(betterSupabase, supabase, spec, { onChange: () => refetch() });
 * ```
 */
export function liveQuery(
  betterSupabase: LiveSource,
  client: RealtimeClient,
  spec: QuerySpec | readonly string[],
  options: LiveQueryOptions,
): LiveSubscription {
  // SAFETY: spec is a list of table names or a QuerySpec, and Array.isArray
  // picked the list.
  const touched = Array.isArray(spec)
    ? (spec as readonly string[])
    : betterSupabase.tablesOf(spec as QuerySpec);
  const tables = touched.filter(
    (table) => betterSupabase.meta.realtime?.[table],
  );
  const unwatched = touched.filter(
    (table) => !betterSupabase.meta.realtime?.[table],
  );
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

  const onTableChange = (table: string) => () => {
    changed.add(table);
    if (timer !== undefined) clearTimeout(timer);
    timer = setTimeout(flush, debounceMs);
  };
  const failed = new Set<string>();
  const onChannelStatus =
    (topic: string): StatusListener =>
    (status, error) => {
      if (closed) return;
      if (status === "error") failed.add(topic);
      else failed.delete(topic);
      if (status === "error") options.onStatus?.("error", error);
      else if (failed.size === 0) options.onStatus?.("subscribed");
    };
  const topics = tables.map((table) => ({
    table,
    topic: liveTopic(betterSupabase.meta, table, options.tenant, options.user),
  }));
  const joinAll = () =>
    topics.map(({ table, topic }) =>
      join(client, topic, onTableChange(table), onChannelStatus(topic)),
    );
  let memberships = joinAll();
  let retryTimer: ReturnType<typeof setTimeout> | undefined;
  let delay = 1000;

  const settle = (attempt: typeof memberships): Promise<void> =>
    Promise.all(attempt.map((member) => member.ready)).then(
      () => {
        if (!closed && tables.length > 0) options.onStatus?.("subscribed");
      },
      (cause: unknown) => {
        const error = cause instanceof Error ? cause : new Error(String(cause));
        if (!closed) {
          options.onStatus?.("error", error);
          if (options.retry !== false) scheduleRetry(attempt);
        }
        throw error;
      },
    );
  const scheduleRetry = (attempt: typeof memberships): void => {
    retryTimer = setTimeout(() => {
      retryTimer = undefined;
      if (closed || attempt !== memberships) return;
      void Promise.all(attempt.map((member) => member.leave()));
      memberships = joinAll();
      options.onStatus?.("joining");
      // Changes made while the channel was down were missed.
      settle(memberships).then(
        () => {
          if (closed) return;
          for (const table of tables) changed.add(table);
          flush();
        },
        () => undefined,
      );
    }, delay);
    delay = Math.min(delay * 2, 30_000);
  };

  options.onStatus?.(tables.length === 0 ? "closed" : "joining");
  const ready = settle(memberships);
  ready.catch(() => undefined);

  const unsubscribe = async (): Promise<void> => {
    if (closed) return;
    closed = true;
    if (timer !== undefined) clearTimeout(timer);
    if (retryTimer !== undefined) clearTimeout(retryTimer);
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

/** What `liveCount` runs the spec with: a `db` from `betterSupabase.connect()` or `createClient()`. */
export interface CountRunner {
  $run(spec: QuerySpec): PromiseLike<Result<unknown>>;
}

export interface LiveCountOptions extends Omit<LiveQueryOptions, "onChange"> {
  readonly onCount: (count: number) => void;
  /** A failed refetch; the previous count stays valid. */
  readonly onError?: (error: DbError) => void;
  /** Count right away. Defaults to `true`; pass `false` when you have a seed. */
  readonly immediate?: boolean;
  /**
   * When the count you already have was taken (epoch ms). Counts again once
   * the channel joins when that is more than a second ago, so a change made
   * before the join is not lost.
   */
  readonly since?: number;
}

/**
 * Keeps a count current: runs the `count` spec (a HEAD request) now, after
 * each debounced change to a table it reads, and after the channel rejoins.
 * Responses that arrive out of order are dropped.
 *
 * ```ts
 * using live = liveCount(betterSupabase, supabase, db, betterSupabase.spec.notes.count(), {
 *   onCount: (count) => render(count),
 * });
 * ```
 */
export function liveCount(
  betterSupabase: LiveSource,
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
      if (result.ok) {
        // SAFETY: the count query spec always resolves to a number.
        options.onCount(result.data as number);
      } else options.onError?.(result.error);
    });
  };
  const live = liveQuery(betterSupabase, client, spec, {
    onChange: refetch,
    ...(options.tenant === undefined ? {} : { tenant: options.tenant }),
    ...(options.user === undefined ? {} : { user: options.user }),
    ...(options.debounceMs === undefined
      ? {}
      : { debounceMs: options.debounceMs }),
    ...(options.onStatus ? { onStatus: options.onStatus } : {}),
  });
  if (options.immediate ?? true) refetch();
  const since = options.since;
  if (since !== undefined) {
    live.ready.then(
      () => {
        if (!closed && Date.now() - since > 1000) refetch();
      },
      () => undefined,
    );
  }
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
