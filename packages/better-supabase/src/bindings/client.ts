import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import type { AuthSnapshot, ClientAuth } from "../client/index.ts";
import type { DbError } from "../core/errors.ts";
import type { QuerySpec } from "../core/spec.ts";
import type {
  EventSchemas,
  PresenceMember,
  PresenceOptions,
  PresenceSubscription,
  RealtimeClient,
  SubscribeOptions,
  SubscriptionStatus,
  TemplateValues,
  Topic,
  TopicHandlers,
  TopicMessage,
} from "../realtime/index.ts";
import type {
  CountRunner,
  LiveCountSeed,
  LiveSource,
} from "../realtime/live.ts";

import { dbError } from "../core/errors.ts";
import { invalidateTables } from "../query/invalidate.ts";
import { liveCount, liveQuery } from "../realtime/live.ts";
import { claimedTenant, sessionUserId, specKey } from "./keys.ts";

/** The parts of `createClient()` the bindings need. */
export interface ClientLike {
  readonly betterSupabase: LiveSource;
  readonly supabase: SupabaseClient;
  readonly auth: ClientAuth;
  readonly db: object;
  readonly queries: object;
}

/** A value that changes, read with `current()` and watched with `subscribe()`. */
export interface Store<T> {
  readonly current: () => T;
  readonly subscribe: (listener: () => void) => () => void;
}

/** What a `bs.action()` Server Action or server function resolves to. */
export type ActionResultOf<T> =
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

/**
 * The input `useAction` passes: a `bs.action()` with an `input` schema also
 * accepts `FormData`, which belongs to `useActionForm`.
 */
export type ActionInputOf<I> = [Exclude<I, FormData>] extends [never]
  ? I
  : Exclude<I, FormData>;

export interface UseActionOptions<I, T> {
  readonly onSuccess?: (data: T, input: I) => void;
  readonly onError?: (error: DbError, input: I) => void;
}

export interface BroadcastOptions extends Omit<SubscribeOptions, "onStatus"> {
  /**
   * A supabase-js client to subscribe with, for apps without the provider.
   * It resubscribes when the client's user changes. Defaults to the
   * provider's client.
   */
  readonly client?: SupabaseClient;
  /** The query client `invalidate` refetches with. Defaults to the provider's. */
  readonly queryClient?: QueryClient;
  /**
   * Refetch after each message: table keys (every query that read one of
   * them), or a function returning query keys. Needs a `queryClient`, here
   * or on the provider.
   */
  readonly invalidate?:
    | readonly string[]
    | ((message: TopicMessage) => readonly (readonly unknown[])[]);
}

export interface LiveQueryHookOptions {
  /**
   * Tenant for tenant-scoped tables. Defaults to the `config.claims.tenant`
   * claim (`tenant_id`, top-level or in `app_metadata`).
   */
  readonly tenant?: string;
  /** Defaults to 100 ms. */
  readonly debounceMs?: number;
}

export interface LiveCountHookOptions extends LiveQueryHookOptions {
  /** The count to show before the first fetch, e.g. from the server. */
  readonly initial?: number;
}

export interface PresenceHookOptions<I> {
  /**
   * The state this client shares while joined. It is tracked after the
   * join and tracked again when its JSON changes; `null` stays untracked.
   */
  readonly state?: I | null;
  /** A supabase-js client for apps without the provider. */
  readonly client?: SupabaseClient;
}

/** The parts of a `defineTopic(..., { presence })` topic the bindings use. */
export interface PresenceTopic<P extends string, I, O> {
  topic(values: TemplateValues<P>): string;
  match(topic: string): TemplateValues<P> | null;
  subscribe(
    client: RealtimeClient,
    values: TemplateValues<P>,
    handlers: Readonly<Record<string, never>>,
    options?: SubscribeOptions & PresenceOptions<O>,
  ): PresenceSubscription<I, O>;
}

/** Who a subscription runs as. */
export interface Caller {
  readonly status: AuthSnapshot["status"];
  readonly userId: string | null;
}

/** The caller of the client's auth store. */
export function callerOf(auth: AuthSnapshot): Caller {
  return { status: auth.status, userId: auth.user?.id ?? null };
}

/**
 * The caller of a plain supabase-js client, for subscriptions made without
 * the provider. `loading` until auth-js reports the first state.
 */
export function plainCaller(supabase: SupabaseClient): Store<Caller> {
  let caller: Caller = { status: "loading", userId: null };
  return {
    current: () => caller,
    subscribe: (listener) => {
      const { data } = supabase.auth.onAuthStateChange((_event, session) => {
        caller = {
          status: session ? "signed-in" : "signed-out",
          userId: session ? sessionUserId(session) : null,
        };
        listener();
      });
      return () => {
        data.subscription.unsubscribe();
      };
    },
  };
}

export interface BroadcastRun<P extends string, E extends EventSchemas> {
  readonly supabase: SupabaseClient;
  readonly topic: Topic<P, E>;
  readonly name: string;
  /** Read on every message, so handlers can change without a resubscribe. */
  readonly latest: () => {
    readonly handlers: TopicHandlers<E> | undefined;
    readonly options: BroadcastOptions | undefined;
  };
  readonly queryClient: QueryClient | undefined;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/** Throws when `invalidate` has no query client to refetch with. */
export function assertInvalidateClient(
  hook: string,
  options: BroadcastOptions | undefined,
  queryClient: QueryClient | undefined,
): void {
  if (options?.invalidate && !queryClient) {
    throw new Error(
      `better-supabase: ${hook}({ invalidate }) needs a queryClient on the provider or in the options`,
    );
  }
}

/**
 * Subscribes to a topic by its rendered name. Returns the function that
 * leaves, or `undefined` when the name does not match the topic.
 */
export function startBroadcast<P extends string, E extends EventSchemas>(
  run: BroadcastRun<P, E>,
): (() => void) | undefined {
  const matched = run.topic.match(run.name);
  if (!matched) return undefined;
  const { queryClient } = run;
  const forward = (payload: unknown, message: TopicMessage) => {
    const current = run.latest();
    // SAFETY: handlers are keyed by table and event, and the payload comes
    // from that table's topic.
    const table = current.handlers as
      | Readonly<
          Record<
            string,
            ((payload: unknown, message: TopicMessage) => void) | undefined
          >
        >
      | undefined;
    (table?.[message.event] ?? table?.["*"])?.(payload, message);
    const invalidate = current.options?.invalidate;
    if (!invalidate || !queryClient) return;
    if (typeof invalidate !== "function") {
      void invalidateTables(queryClient, invalidate);
      return;
    }
    for (const queryKey of invalidate(message))
      void queryClient.invalidateQueries({ queryKey });
  };
  const self = run.latest().options?.self;
  const subscription = run.topic.subscribe(
    run.supabase,
    matched,
    { "*": forward },
    {
      ...(self === undefined ? {} : { self }),
      onStatus: run.onStatus,
      onInvalid: (message, issues) =>
        run.latest().options?.onInvalid?.(message, issues),
    },
  );
  return () => {
    void subscription.unsubscribe();
    run.onStatus("closed");
  };
}

export interface LiveQueryRun {
  readonly client: ClientLike;
  readonly queryClient: QueryClient;
  readonly spec: QuerySpec;
  readonly auth: AuthSnapshot;
  readonly options: LiveQueryHookOptions;
  /** True when the same spec joins again and missed changes while away. */
  readonly resumed: boolean;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/** The key a live subscription restarts on: spec, tenant and caller. */
export function liveKey(
  client: ClientLike,
  spec: QuerySpec | null | undefined,
  auth: AuthSnapshot,
  options: LiveQueryHookOptions,
): string | null {
  if (!spec || auth.status === "loading") return null;
  const tenant =
    options.tenant ?? claimedTenant(auth, client.betterSupabase.meta);
  return JSON.stringify([
    specKey(spec),
    tenant ?? null,
    auth.user?.id ?? null,
    options.debounceMs ?? null,
  ]);
}

/** Invalidates the cached queries that read a table whenever one changes. */
export function startLiveQuery(run: LiveQueryRun): () => void {
  const { client, queryClient, options } = run;
  const tenant =
    options.tenant ?? claimedTenant(run.auth, client.betterSupabase.meta);
  const userId = run.auth.user?.id ?? null;
  const live = liveQuery(client.betterSupabase, client.supabase, run.spec, {
    onChange: (tables) => void invalidateTables(queryClient, tables),
    onStatus: run.onStatus,
    ...(tenant === undefined ? {} : { tenant }),
    ...(userId === null ? {} : { user: userId }),
    ...(options.debounceMs === undefined
      ? {}
      : { debounceMs: options.debounceMs }),
  });
  if (run.resumed) {
    live.ready.then(
      () => void invalidateTables(queryClient, live.tables),
      () => undefined,
    );
  }
  return () => {
    void live.unsubscribe();
  };
}

/** A count spec or a `bs.liveCount()` seed. */
export type LiveCountSource =
  | QuerySpec<string, "count", number>
  | LiveCountSeed
  | null
  | undefined;

/** Splits a count source into its spec and the seed's count and time. */
export function countSource(
  source: LiveCountSource,
  options: LiveCountHookOptions,
): {
  readonly spec: QuerySpec<string, "count", number> | null;
  readonly initial: number | undefined;
  readonly seedAt: number | undefined;
  readonly seeded: boolean;
} {
  const seed = source && "spec" in source ? source : undefined;
  // SAFETY: source is a seed with a count spec or a plain count spec, and
  // the in check ruled out the seed.
  const spec = (seed ? seed.spec : source) as
    | QuerySpec<string, "count", number>
    | null
    | undefined;
  return {
    spec: spec ?? null,
    initial: seed?.count ?? options.initial,
    seedAt: seed?.at,
    seeded: seed !== undefined && seed.count !== null,
  };
}

export interface CountState {
  readonly key: string | null;
  readonly count: number | undefined;
  readonly at: number;
  readonly error: DbError | undefined;
}

export const NO_COUNT: CountState = {
  key: null,
  count: undefined,
  at: 0,
  error: undefined,
};

export interface LiveCountRun {
  readonly client: ClientLike;
  readonly spec: QuerySpec<string, "count", number>;
  readonly key: string;
  readonly auth: AuthSnapshot;
  readonly options: LiveCountHookOptions;
  /** Count at once: no initial count and no earlier join of this key. */
  readonly immediate: boolean;
  readonly since: number | undefined;
  readonly onState: (update: (last: CountState) => CountState) => void;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/** Refetches the count after each debounced change to a table it reads. */
export function startLiveCount(run: LiveCountRun): () => void {
  const { client, key, options } = run;
  const tenant =
    options.tenant ?? claimedTenant(run.auth, client.betterSupabase.meta);
  const userId = run.auth.user?.id ?? null;
  // SAFETY: the client db runs count specs.
  const live = liveCount(
    client.betterSupabase,
    client.supabase,
    client.db as CountRunner,
    run.spec,
    {
      immediate: run.immediate,
      ...(run.since === undefined ? {} : { since: run.since }),
      onCount: (count) => {
        const at = Date.now();
        run.onState(() => ({ key, count, at, error: undefined }));
      },
      onError: (error) => {
        run.onState((last) => ({
          key,
          count: last.key === key ? last.count : undefined,
          at: last.key === key ? last.at : 0,
          error,
        }));
      },
      onStatus: run.onStatus,
      ...(tenant === undefined ? {} : { tenant }),
      ...(userId === null ? {} : { user: userId }),
      ...(options.debounceMs === undefined
        ? {}
        : { debounceMs: options.debounceMs }),
    },
  );
  return () => {
    void live.unsubscribe();
  };
}

/** The count to show: the client's, unless a newer server seed arrived. */
export function shownCount(
  state: CountState,
  key: string | null,
  source: ReturnType<typeof countSource>,
): { readonly count: number | undefined; readonly error: DbError | undefined } {
  const fresh = state.key === key;
  const seedNewer =
    source.seedAt !== undefined && source.seeded && source.seedAt > state.at;
  return {
    count:
      fresh && state.count !== undefined && !seedNewer
        ? state.count
        : source.initial,
    error: fresh ? state.error : undefined,
  };
}

const NO_HANDLERS: Readonly<Record<string, never>> = {};

/** A presence join that tracks the `state` option once per distinct value. */
export interface PresenceJoin<I> {
  readonly track: (state: I) => Promise<DbError | undefined>;
  readonly untrack: () => Promise<DbError | undefined>;
  /** Tracks or untracks `state` when its JSON differs from the last one. */
  sync(state: I | null | undefined): void;
  leave(): void;
}

/** Joins a presence topic by its rendered name, or `undefined` when it does not match. */
export function joinPresence<P extends string, I, O>(
  supabase: SupabaseClient,
  topic: PresenceTopic<P, I, O>,
  name: string,
  handlers: {
    readonly onStatus: (status: SubscriptionStatus) => void;
    readonly onPresence: (members: readonly PresenceMember<O>[]) => void;
  },
): PresenceJoin<I> | undefined {
  const matched = topic.match(name);
  if (!matched) return undefined;
  const joined = topic.subscribe(supabase, matched, NO_HANDLERS, handlers);
  let tracked: string | undefined;
  return {
    track: async (state) => {
      const result = await joined.track(state);
      return result.ok ? undefined : result.error;
    },
    untrack: async () => {
      const result = await joined.untrack();
      return result.ok ? undefined : result.error;
    },
    sync(state) {
      const key = state === undefined ? undefined : JSON.stringify(state);
      if (key === undefined || key === tracked) return;
      tracked = key;
      if (state === null || state === undefined) void joined.untrack();
      else void joined.track(state);
    },
    leave() {
      void joined.unsubscribe();
    },
  };
}

/** The error `track` and `untrack` return before the join. */
export const notJoined = (): Promise<DbError> =>
  Promise.resolve(
    dbError(
      "invalid_request",
      "better-supabase: the presence topic is not joined",
    ),
  );

export interface ActionState<I, T> {
  /** True while a run is in flight. */
  readonly pending: boolean;
  /** The inputs of the runs in flight, e.g. to dim one table row. */
  readonly pendingInputs: readonly I[];
  /** The input of the latest run in flight. */
  readonly pendingInput: I | undefined;
  /** The data of the last successful run. */
  readonly data: T | undefined;
  /** The error of the last run, until the next one starts. */
  readonly error: DbError | undefined;
}

export interface ActionRunner<I, T> extends Store<ActionState<I, T>> {
  readonly run: (input: I) => Promise<ActionResultOf<T>>;
  readonly reset: () => void;
}

/**
 * Tracks the runs of an action outside React: the inputs in flight, the
 * last data and the last error. `latest` is read on each run, so the action
 * and the callbacks can change between runs.
 */
export function createActionRunner<I, T>(
  latest: () => {
    readonly action: (input: I) => Promise<ActionResultOf<T>>;
    readonly options: UseActionOptions<I, T>;
  },
): ActionRunner<I, T> {
  const listeners = new Set<() => void>();
  let inFlight: readonly { readonly input: I }[] = [];
  let data: T | undefined;
  let error: DbError | undefined;
  let state: ActionState<I, T> = snapshot();

  function snapshot(): ActionState<I, T> {
    const pendingInputs = inFlight.map((item) => item.input);
    return {
      pending: inFlight.length > 0,
      pendingInputs,
      pendingInput: pendingInputs.at(-1),
      data,
      error,
    };
  }
  const emit = (): void => {
    state = snapshot();
    for (const listener of listeners) listener();
  };

  return {
    current: () => state,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    run: async (input) => {
      // Each run gets its own entry, so two runs with equal inputs stay apart.
      const entry = { input };
      inFlight = [...inFlight, entry];
      error = undefined;
      emit();
      const done = (): void => {
        inFlight = inFlight.filter((item) => item !== entry);
      };
      const { action, options } = latest();
      let result: ActionResultOf<T>;
      try {
        result = await action(input);
      } catch (cause) {
        done();
        emit();
        throw cause;
      }
      done();
      if (result.ok) data = result.data;
      else error = result.error;
      emit();
      if (result.ok) options.onSuccess?.(result.data, input);
      else options.onError?.(result.error, input);
      return result;
    },
    reset: () => {
      data = undefined;
      error = undefined;
      emit();
    },
  };
}

/**
 * One run per key: `update` restarts `start` when the key changes and stops
 * the run when the key is `null`.
 */
export function keyed(): {
  readonly update: (
    key: string | null,
    start: () => (() => void) | undefined,
  ) => void;
  readonly stop: () => void;
} {
  let current: { key: string; stop: (() => void) | undefined } | undefined;
  return {
    update: (key, start) => {
      if (current?.key === key) return;
      current?.stop?.();
      current = key === null ? undefined : { key, stop: start() };
    },
    stop: () => {
      current?.stop?.();
      current = undefined;
    },
  };
}
