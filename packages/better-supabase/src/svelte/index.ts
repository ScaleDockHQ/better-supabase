import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import { getContext, onMount, setContext } from "svelte";
import { createSubscriber } from "svelte/reactivity";

import type { AuthSession } from "../auth/view.ts";
import type {
  ActionInputOf,
  ActionResultOf,
  ActionState,
  BroadcastOptions,
  Caller,
  ClientLike,
  CountState,
  LiveCountHookOptions,
  LiveCountSource,
  LiveQueryHookOptions,
  PresenceHookOptions,
  PresenceJoin,
  PresenceTopic,
  Store,
  UseActionOptions,
} from "../bindings/client.ts";
import type { AuthSnapshot } from "../client/index.ts";
import type { DbError } from "../core/errors.ts";
import type { QuerySpec } from "../core/spec.ts";
import type {
  EventSchemas,
  PresenceMember,
  SubscriptionStatus,
  TemplateValues,
  Topic,
  TopicHandlers,
} from "../realtime/index.ts";

import {
  assertInvalidateClient,
  callerOf,
  countSource,
  createActionRunner,
  joinPresence,
  keyed,
  liveKey,
  NO_COUNT,
  notJoined,
  plainCaller,
  shownCount,
  startBroadcast,
  startLiveCount,
  startLiveQuery,
} from "../bindings/client.ts";
import { clearOnUserChange } from "../query/user-change.ts";

export type {
  ActionInputOf,
  ActionResultOf,
  ActionState,
  BroadcastOptions,
  ClientLike,
  LiveCountHookOptions,
  LiveCountSource,
  LiveQueryHookOptions,
  PresenceHookOptions,
  PresenceTopic,
  UseActionOptions,
} from "../bindings/client.ts";
export type { AuthSnapshot } from "../client/index.ts";
export type { AuthSession } from "../auth/view.ts";
export { fieldErrorsOf } from "../react/field-errors.ts";

/** A value read through `.current`, reactive in templates, `$derived` and `$effect`. */
export interface Current<T> {
  readonly current: T;
}

export interface LiveCount {
  /** `undefined` until the first count arrives. */
  readonly count: number | undefined;
  readonly status: SubscriptionStatus;
  /** The last failed refetch; the previous count stays. */
  readonly error: DbError | undefined;
}

export interface Presence<I, O> {
  /** Everyone on the topic, this client included, from the last sync. */
  readonly members: readonly PresenceMember<O>[];
  readonly status: SubscriptionStatus;
  /** Shares a state now; the `state` option tracks one for you. */
  readonly track: (state: I) => Promise<DbError | undefined>;
  readonly untrack: () => Promise<DbError | undefined>;
}

export interface SveltePresenceOptions<I> extends Omit<
  PresenceHookOptions<I>,
  "state"
> {
  readonly state?: () => I | null | undefined;
}

export interface ActionHandle<I, T> extends ActionState<I, T> {
  /** Runs the action; resolves with its result. */
  readonly run: (input: I) => Promise<ActionResultOf<T>>;
  readonly reset: () => void;
}

/** The claims type of a client's `betterSupabase.claims(schema)`, `unknown` without one. */
export type ClaimsOf<B extends ClientLike> = B["betterSupabase"] extends {
  readonly claimsSchema: StandardSchemaV1<unknown, infer C> | undefined;
}
  ? C
  : unknown;

/** The profile type of a client's `betterSupabase.userMetadata(schema)`, `unknown` without one. */
export type ProfileOf<B extends ClientLike> = B["betterSupabase"] extends {
  readonly userMetadataSchema: StandardSchemaV1<unknown, infer P> | undefined;
}
  ? P
  : unknown;

/**
 * The client bound to Svelte. Inputs are getters (`() => spec`), so the
 * subscriptions follow `$state` and `$props`. A subscription starts when a
 * template, `$derived` or `$effect` reads one of its fields and stops when
 * nothing reads it any more.
 */
export interface BetterSvelte<B extends ClientLike = ClientLike> {
  readonly client: B;
  readonly queryClient: QueryClient | undefined;
  /** Repositories bound to the current session. */
  readonly db: B["db"];
  /** TanStack Query option factories: `createQuery(() => bs.queries.customers.findMany())`. */
  readonly queries: B["queries"];
  readonly supabase: SupabaseClient;
  /** The session state for UI: `loading`, `signed-out` or `signed-in`. */
  readonly auth: Current<AuthSnapshot>;
  broadcast<P extends string, E extends EventSchemas>(
    topic: Topic<P, E>,
    values: () => TemplateValues<P> | null | undefined,
    handlers?: TopicHandlers<E>,
    options?: BroadcastOptions,
  ): Current<SubscriptionStatus>;
  liveQuery(
    spec: () => QuerySpec | null | undefined,
    options?: LiveQueryHookOptions,
  ): Current<SubscriptionStatus>;
  liveCount(
    source: () => LiveCountSource,
    options?: LiveCountHookOptions,
  ): LiveCount;
  presence<P extends string, I, O>(
    topic: PresenceTopic<P, I, O>,
    values: () => TemplateValues<P> | null | undefined,
    options?: SveltePresenceOptions<I>,
  ): Presence<I, O>;
  action<I, T>(
    action: (input: I) => Promise<ActionResultOf<T>>,
    options?: UseActionOptions<ActionInputOf<I>, T>,
  ): ActionHandle<ActionInputOf<I>, T>;
}

export interface BetterSvelteOptions {
  /** better-supabase queries are reset when the user signs out or changes. */
  readonly queryClient?: QueryClient;
}

/** Reads a store reactively: the caller re-runs when the store changes. */
function reactive<T>(store: Store<T>): Current<T> {
  const subscribe = createSubscriber((update) => store.subscribe(update));
  return {
    get current() {
      subscribe();
      return store.current();
    },
  };
}

/**
 * A subscription keyed by `key()`. The returned function goes in each
 * getter: it registers the reader, then restarts the subscription when the
 * key (read in the reader's tracking context) changed. Notifications are
 * queued, since a getter may run inside `$derived`, where writes throw.
 */
function followed(
  key: () => string | null,
  start: (key: string, notify: () => void) => (() => void) | undefined,
): () => void {
  const run = keyed();
  let notify: (() => void) | undefined;
  const queued = (): void => {
    queueMicrotask(() => notify?.());
  };
  const update = (): void => {
    const next = key();
    run.update(next, () => (next === null ? undefined : start(next, queued)));
  };
  const subscribe = createSubscriber((changed) => {
    notify = changed;
    update();
    return () => {
      notify = undefined;
      run.stop();
    };
  });
  return () => {
    subscribe();
    if (notify) update();
  };
}

const NO_MEMBERS: readonly never[] = [];

/** Binds a client to Svelte without a component context, e.g. in tests or a module. */
export function createBetterSvelte<B extends ClientLike>(
  client: B,
  options: BetterSvelteOptions = {},
): BetterSvelte<B> {
  const { queryClient } = options;
  const auth = reactive(client.auth);
  const plainCallers = new WeakMap<SupabaseClient, Current<Caller>>();
  const callerFor = (supabase: SupabaseClient | undefined): Current<Caller> => {
    if (supabase === undefined)
      return {
        get current() {
          return callerOf(auth.current);
        },
      };
    let caller = plainCallers.get(supabase);
    if (!caller) {
      caller = reactive(plainCaller(supabase));
      plainCallers.set(supabase, caller);
    }
    return caller;
  };

  return {
    client,
    queryClient,
    db: client.db,
    queries: client.queries,
    supabase: client.supabase,
    auth,
    broadcast(topic, values, handlers, options) {
      const supabase = options?.client ?? client.supabase;
      const forQuery = options?.queryClient ?? queryClient;
      assertInvalidateClient("broadcast", options, forQuery);
      const caller = callerFor(options?.client);
      let status: SubscriptionStatus = "closed";
      const name = (): string | null => {
        const current = values();
        return current ? topic.topic(current) : null;
      };
      const track = followed(
        () => {
          const current = name();
          const who = caller.current;
          if (current === null || who.status === "loading") return null;
          return JSON.stringify([current, who.userId]);
        },
        (_key, notify) => {
          const current = name();
          if (current === null) return;
          return startBroadcast({
            supabase,
            topic,
            name: current,
            latest: () => ({ handlers, options }),
            queryClient: forQuery,
            onStatus: (next) => {
              status = next;
              notify();
            },
          });
        },
      );
      return {
        get current() {
          track();
          return status;
        },
      };
    },
    liveQuery(spec, options = {}) {
      let status: SubscriptionStatus = "closed";
      let joined: string | null = null;
      const track = followed(
        () => {
          const current = spec();
          if (current && !queryClient) {
            throw new Error(
              "better-supabase: liveQuery needs setBetterSupabase(bs, { queryClient })",
            );
          }
          return liveKey(client, current, auth.current, options);
        },
        (key, notify) => {
          const current = spec();
          if (!current || !queryClient) return;
          const resumed = joined === key;
          joined = key;
          return startLiveQuery({
            client,
            queryClient,
            spec: current,
            auth: client.auth.current(),
            options,
            resumed,
            onStatus: (next) => {
              status = next;
              notify();
            },
          });
        },
      );
      return {
        get current() {
          track();
          return status;
        },
      };
    },
    liveCount(source, options = {}) {
      let status: SubscriptionStatus = "closed";
      let state: CountState = NO_COUNT;
      let joined: { key: string; at: number } | null = null;
      const parsed = () => countSource(source(), options);
      const key = () => liveKey(client, parsed().spec, auth.current, options);
      const track = followed(key, (next, notify) => {
        const { spec, initial, seedAt } = parsed();
        if (!spec) return;
        const previous = joined?.key === next ? joined : null;
        joined = { key: next, at: previous?.at ?? seedAt ?? 0 };
        return startLiveCount({
          client,
          spec,
          key: next,
          auth: client.auth.current(),
          options,
          immediate: initial === undefined && !previous,
          since: previous ? previous.at : seedAt,
          onState: (update) => {
            state = update(state);
            if (joined?.key === next) joined = { key: next, at: state.at };
            notify();
          },
          onStatus: (value) => {
            status = value;
            notify();
          },
        });
      });
      const shown = () => {
        track();
        return shownCount(state, key(), parsed());
      };
      return {
        get count() {
          return shown().count;
        },
        get status() {
          track();
          return status;
        },
        get error() {
          return shown().error;
        },
      };
    },
    presence<P extends string, I, O>(
      topic: PresenceTopic<P, I, O>,
      values: () => TemplateValues<P> | null | undefined,
      options: SveltePresenceOptions<I> = {},
    ): Presence<I, O> {
      const supabase = options.client ?? client.supabase;
      const caller = callerFor(options.client);
      let members: readonly PresenceMember<O>[] = NO_MEMBERS;
      let status: SubscriptionStatus = "closed";
      let join: PresenceJoin<I> | undefined;
      const name = (): string | null => {
        const current = values();
        return current ? topic.topic(current) : null;
      };
      const follow = followed(
        () => {
          const current = name();
          const who = caller.current;
          if (current === null || who.status === "loading") return null;
          return JSON.stringify([current, who.userId]);
        },
        (_key, notify) => {
          const current = name();
          if (current === null) return;
          const joined = joinPresence(supabase, topic, current, {
            onStatus: (next) => {
              status = next;
              notify();
            },
            onPresence: (next) => {
              members = next;
              notify();
            },
          });
          if (!joined) return;
          join = joined;
          joined.sync(options.state?.());
          return () => {
            join = undefined;
            members = NO_MEMBERS;
            status = "closed";
            joined.leave();
            notify();
          };
        },
      );
      const track = (): void => {
        follow();
        join?.sync(options.state?.());
      };
      return {
        get members() {
          track();
          return members;
        },
        get status() {
          track();
          return status;
        },
        track: (state) => join?.track(state) ?? notJoined(),
        untrack: () => join?.untrack() ?? notJoined(),
      };
    },
    action<I, T>(
      action: (input: I) => Promise<ActionResultOf<T>>,
      options: UseActionOptions<ActionInputOf<I>, T> = {},
    ): ActionHandle<ActionInputOf<I>, T> {
      // SAFETY: ActionInputOf<I> only drops FormData, which `I` accepts.
      const call = action as (
        input: ActionInputOf<I>,
      ) => Promise<ActionResultOf<T>>;
      const runner = createActionRunner(() => ({ action: call, options }));
      const state = reactive(runner);
      return {
        run: runner.run,
        reset: runner.reset,
        get pending() {
          return state.current.pending;
        },
        get pendingInputs() {
          return state.current.pendingInputs;
        },
        get pendingInput() {
          return state.current.pendingInput;
        },
        get data() {
          return state.current.data;
        },
        get error() {
          return state.current.error;
        },
      };
    },
  };
}

const CLIENT = Symbol("better-supabase");
const SESSION = Symbol("better-supabase-session");

/**
 * Binds the client for the components below, in the root layout. With a
 * `queryClient`, better-supabase queries are reset when the caller changes.
 *
 * ```svelte
 * <script lang="ts">
 *   setBetterSupabase(bs, { queryClient });
 * </script>
 * ```
 */
export function setBetterSupabase<B extends ClientLike>(
  client: B,
  options: BetterSvelteOptions = {},
): BetterSvelte<B> {
  const bound = createBetterSvelte(client, options);
  const { queryClient } = options;
  if (queryClient) onMount(() => clearOnUserChange(queryClient, client.auth));
  return setContext(CLIENT, bound);
}

/** The client `setBetterSupabase` bound, typed with `getBetterSupabase<typeof bs>()`. */
export function getBetterSupabase<
  B extends ClientLike = ClientLike,
>(): BetterSvelte<B> {
  const bound = getContext<BetterSvelte<B> | undefined>(CLIENT);
  if (!bound) {
    throw new Error(
      "better-supabase: call setBetterSupabase(bs) in a parent component",
    );
  }
  return bound;
}

/** The session state for UI. Call during component setup. */
export function useAuth(): Current<AuthSnapshot> {
  return getBetterSupabase().auth;
}

/** Subscribes to a topic while read. Call during component setup. */
export function useBroadcast<P extends string, E extends EventSchemas>(
  topic: Topic<P, E>,
  values: () => TemplateValues<P> | null | undefined,
  handlers?: TopicHandlers<E>,
  options?: BroadcastOptions,
): Current<SubscriptionStatus> {
  return getBetterSupabase().broadcast(topic, values, handlers, options);
}

/**
 * Keeps a query fresh while read. Call during component setup.
 *
 * ```svelte
 * <script lang="ts">
 *   const live = useLiveQuery(() => betterSupabase.spec.customers.findMany());
 * </script>
 * <span data-status={live.current}></span>
 * ```
 */
export function useLiveQuery(
  spec: () => QuerySpec | null | undefined,
  options?: LiveQueryHookOptions,
): Current<SubscriptionStatus> {
  return getBetterSupabase().liveQuery(spec, options);
}

/** A count that stays current while read. Call during component setup. */
export function useLiveCount(
  source: () => LiveCountSource,
  options?: LiveCountHookOptions,
): LiveCount {
  return getBetterSupabase().liveCount(source, options);
}

/** Joins a presence topic while read. Call during component setup. */
export function usePresence<P extends string, I, O>(
  topic: PresenceTopic<P, I, O>,
  values: () => TemplateValues<P> | null | undefined,
  options?: SveltePresenceOptions<I>,
): Presence<I, O> {
  return getBetterSupabase().presence(topic, values, options);
}

/** Tracks the runs of a server action or form action. */
export function useAction<I, T>(
  action: (input: I) => Promise<ActionResultOf<T>>,
  options?: UseActionOptions<ActionInputOf<I>, T>,
): ActionHandle<ActionInputOf<I>, T> {
  return getBetterSupabase().action(action, options);
}

/** Shares a server-verified session (from `+layout.ts` data) with the components below. */
export function setSession(session: () => AuthSession): void {
  setContext(SESSION, session);
}

/** The session from the nearest `setSession()`, typed with `useSession<Claims, Profile>()`. */
export function useSession<C = unknown, P = unknown>(): Current<
  AuthSession<C, P>
> {
  const session = getContext<(() => AuthSession) | undefined>(SESSION);
  if (!session) {
    throw new Error(
      "better-supabase: useSession() needs setSession(() => data.session) in a parent component",
    );
  }
  return {
    get current() {
      // SAFETY: setSession receives `bs.session()` from the same
      // `betterSupabase`, whose schemas fix `C` and `P`.
      return session() as AuthSession<C, P>;
    },
  };
}
