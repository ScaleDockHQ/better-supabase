import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import {
  type Accessor,
  type Context as SolidContext,
  createComponent,
  createContext,
  createEffect,
  createMemo,
  createSignal,
  type JSX,
  onCleanup,
  onMount,
  untrack,
  useContext as useSolidContext,
} from "solid-js";

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

import { supportOf, type SupportView } from "../auth/support-view.ts";
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
export type { SupportView } from "../auth/support-view.ts";
export { fieldErrorsOf } from "../react/field-errors.ts";

/** A value, or an accessor Solid tracks. */
export type MaybeAccessor<T> = T | Accessor<T>;

function read<T>(value: MaybeAccessor<T>): T {
  // SAFETY: the values these primitives take (topic values, specs, seeds,
  // presence state) are never functions, so a function is an accessor.
  return typeof value === "function" ? (value as Accessor<T>)() : value;
}

interface Context {
  readonly client: ClientLike;
  readonly queryClient: QueryClient | undefined;
  readonly auth: Accessor<AuthSnapshot>;
  readonly session: Accessor<AuthSession | undefined> | undefined;
}

const ClientContext: SolidContext<Context | undefined> = createContext<
  Context | undefined
>();

export interface BetterSupabaseProviderProps {
  readonly client: ClientLike;
  /** better-supabase queries are reset when the user signs out or changes. */
  readonly queryClient?: QueryClient;
  /** A server-verified session (`createAsync(() => getSession())`) for `useSession()`. */
  readonly session?: Accessor<AuthSession | undefined>;
  readonly children?: JSX.Element;
}

/** Provides the better-supabase client to the primitives. */
export function BetterSupabaseProvider(
  props: BetterSupabaseProviderProps,
): JSX.Element {
  const { client, queryClient } = props;
  const [auth, setAuth] = createSignal(client.auth.current());
  onMount(() => {
    setAuth(client.auth.current());
    onCleanup(
      client.auth.subscribe(() => {
        setAuth(client.auth.current());
      }),
    );
    if (queryClient) onCleanup(clearOnUserChange(queryClient, client.auth));
  });
  const value: Context = {
    client,
    queryClient,
    auth,
    session: props.session,
  };
  return createComponent(ClientContext.Provider, {
    value,
    get children() {
      return props.children;
    },
  });
}

function useContext(): Context {
  const context = useSolidContext(ClientContext);
  if (!context) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider client={bs}>",
    );
  }
  return context;
}

/** The session state for UI: `loading`, `signed-out` or `signed-in` with the user and claims. */
export function useAuth(): Accessor<AuthSnapshot> {
  return useContext().auth;
}

export function useSupabase(): SupabaseClient {
  return useContext().client.supabase;
}

/** The session passed to `<BetterSupabaseProvider session={...}>`, `undefined` while it loads. */
export function useSession<C = unknown, P = unknown>(): Accessor<
  AuthSession<C, P> | undefined
> {
  const { session } = useContext();
  if (!session) {
    throw new Error(
      "better-supabase: useSession() needs <BetterSupabaseProvider session={...}>",
    );
  }
  // SAFETY: the provider receives `bs.session()` from the same
  // `betterSupabase`, whose schemas fix `C` and `P`.
  return session as Accessor<AuthSession<C, P> | undefined>;
}

/** The support session the page renders in, or `undefined` for a normal session. */
export function useSupportSession(): Accessor<SupportView | undefined> {
  const session = useSession();
  return () => {
    const current = session();
    return current ? supportOf(current) : undefined;
  };
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

export interface BetterPrimitives<B extends ClientLike> {
  /** Repositories bound to the current session. */
  readonly useDb: () => B["db"];
  /** TanStack Query option factories: `useQuery(() => useQueries().customers.findMany())`. */
  readonly useQueries: () => B["queries"];
  readonly useSupabase: () => SupabaseClient;
  readonly useAuth: () => Accessor<AuthSnapshot>;
  readonly useSession: () => Accessor<
    AuthSession<ClaimsOf<B>, ProfileOf<B>> | undefined
  >;
}

/**
 * Primitives typed for your schema.
 *
 * ```ts
 * export const { useDb, useQueries, useAuth } = createBindings<typeof bs>();
 * ```
 */
export function createBindings<B extends ClientLike>(): BetterPrimitives<B> {
  return {
    useDb: () => useContext().client.db,
    useQueries: () => useContext().client.queries,
    useSupabase,
    useAuth,
    useSession: useSession<ClaimsOf<B>, ProfileOf<B>>,
  };
}

/** Restarts `start` when `key` changes; stops it with the owner. */
function follow(
  key: Accessor<string | null>,
  start: (key: string) => (() => void) | undefined,
): void {
  const run = keyed();
  createEffect(() => {
    const next = key();
    untrack(() => {
      run.update(next, () => (next === null ? undefined : start(next)));
    });
  });
  onCleanup(run.stop);
}

function useCaller(
  context: Context | undefined,
  client: SupabaseClient | undefined,
): Accessor<Caller> {
  if (context && client === undefined) return () => callerOf(context.auth());
  const supabase = client ?? context?.client.supabase;
  if (!supabase) throw new Error("better-supabase: no supabase client");
  const store = plainCaller(supabase);
  const [caller, setCaller] = createSignal(store.current());
  onMount(() => {
    onCleanup(
      store.subscribe(() => {
        setCaller(store.current());
      }),
    );
  });
  return caller;
}

function supabaseFor(
  hook: string,
  context: Context | undefined,
  client: SupabaseClient | undefined,
): SupabaseClient {
  const supabase = client ?? context?.client.supabase;
  if (!supabase) {
    throw new Error(
      `better-supabase: ${hook} needs <BetterSupabaseProvider client={bs}> or { client: supabase }`,
    );
  }
  return supabase;
}

/**
 * Subscribes to a topic while the owner lives. A `null` value pauses. It
 * resubscribes when the topic values or the signed-in user change.
 *
 * ```ts
 * useBroadcast(customersTopic, () => ({ organizationId: org() }), {}, { invalidate: ['customers'] });
 * ```
 */
export function useBroadcast<P extends string, E extends EventSchemas>(
  topic: Topic<P, E>,
  values: MaybeAccessor<TemplateValues<P> | null | undefined>,
  handlers?: TopicHandlers<E>,
  options?: BroadcastOptions,
): Accessor<SubscriptionStatus> {
  const context = useSolidContext(ClientContext);
  const supabase = supabaseFor("useBroadcast", context, options?.client);
  const queryClient = options?.queryClient ?? context?.queryClient;
  assertInvalidateClient("useBroadcast", options, queryClient);
  const caller = useCaller(context, options?.client);
  const [status, setStatus] = createSignal<SubscriptionStatus>("closed");
  const name = createMemo(() => {
    const current = read(values);
    return current ? topic.topic(current) : null;
  });
  follow(
    createMemo(() => {
      const current = name();
      if (current === null || caller().status === "loading") return null;
      return JSON.stringify([current, caller().userId]);
    }),
    () => {
      const current = name();
      if (current === null) return;
      return startBroadcast({
        supabase,
        topic,
        name: current,
        latest: () => ({ handlers, options }),
        queryClient,
        onStatus: (next) => {
          setStatus(next);
        },
      });
    },
  );
  return status;
}

/**
 * Keeps a query fresh: invalidates every cached query that read a table the
 * spec touches whenever one of them changes. A `null` spec pauses.
 *
 * ```ts
 * useLiveQuery(() => betterSupabase.spec.customers.findMany({ where: { orgId: org() } }));
 * ```
 */
export function useLiveQuery(
  spec: MaybeAccessor<QuerySpec | null | undefined>,
  options: LiveQueryHookOptions = {},
): Accessor<SubscriptionStatus> {
  const { client, queryClient, auth } = useContext();
  const [status, setStatus] = createSignal<SubscriptionStatus>("closed");
  let joined: string | null = null;
  const current = createMemo(() => read(spec));
  follow(
    createMemo(() => {
      const value = current();
      if (value && !queryClient) {
        throw new Error(
          "better-supabase: useLiveQuery needs <BetterSupabaseProvider queryClient={...}>",
        );
      }
      return liveKey(client, value, auth(), options);
    }),
    (key) => {
      const value = current();
      if (!value || !queryClient) return;
      const resumed = joined === key;
      joined = key;
      return startLiveQuery({
        client,
        queryClient,
        spec: value,
        auth: auth(),
        options,
        resumed,
        onStatus: (next) => {
          setStatus(next);
        },
      });
    },
  );
  return status;
}

export interface LiveCount {
  /** `undefined` until the first count arrives. */
  readonly count: number | undefined;
  readonly status: SubscriptionStatus;
  /** The last failed refetch; the previous count stays. */
  readonly error: DbError | undefined;
}

/**
 * A count that stays current: refetches only the `count` spec after each
 * debounced change to a table it reads. Takes a spec or a `bs.liveCount()`
 * seed; `null` pauses. The returned object's fields are reactive.
 *
 * ```tsx
 * const unread = useLiveCount(() => betterSupabase.spec.messages.count({ where: { read: false } }));
 * <span>{unread.count}</span>
 * ```
 */
export function useLiveCount(
  source: MaybeAccessor<LiveCountSource>,
  options: LiveCountHookOptions = {},
): LiveCount {
  const { client, auth } = useContext();
  const [status, setStatus] = createSignal<SubscriptionStatus>("closed");
  const [state, setState] = createSignal<CountState>(NO_COUNT);
  let joined: { key: string; at: number } | null = null;
  const parsed = createMemo(() => countSource(read(source), options));
  const key = createMemo(() => liveKey(client, parsed().spec, auth(), options));
  follow(key, (next) => {
    const { spec, initial, seedAt } = parsed();
    if (!spec) return;
    const previous = joined?.key === next ? joined : null;
    joined = { key: next, at: previous?.at ?? seedAt ?? 0 };
    return startLiveCount({
      client,
      spec,
      key: next,
      auth: auth(),
      options,
      immediate: initial === undefined && !previous,
      since: previous ? previous.at : seedAt,
      onState: (update) => {
        const value = setState(update);
        if (joined?.key === next) joined = { key: next, at: value.at };
      },
      onStatus: (next) => {
        setStatus(next);
      },
    });
  });
  const shown = createMemo(() => shownCount(state(), key(), parsed()));
  return {
    get count() {
      return shown().count;
    },
    get status() {
      return status();
    },
    get error() {
      return shown().error;
    },
  };
}

export interface Presence<I, O> {
  /** Everyone on the topic, this client included, from the last sync. */
  readonly members: readonly PresenceMember<O>[];
  readonly status: SubscriptionStatus;
  /** Shares a state now; the `state` option tracks one for you. */
  readonly track: (state: I) => Promise<DbError | undefined>;
  readonly untrack: () => Promise<DbError | undefined>;
}

export interface SolidPresenceOptions<I> extends Omit<
  PresenceHookOptions<I>,
  "state"
> {
  readonly state?: MaybeAccessor<I | null | undefined>;
}

const NO_MEMBERS: readonly never[] = [];

/**
 * Joins a presence topic while the owner lives and returns who is on it. A
 * `null` value pauses. The returned object's fields are reactive.
 *
 * ```ts
 * const room = usePresence(roomTopic, () => ({ roomId: id() }), { state: () => ({ name: name() }) });
 * ```
 */
export function usePresence<P extends string, I, O>(
  topic: PresenceTopic<P, I, O>,
  values: MaybeAccessor<TemplateValues<P> | null | undefined>,
  options: SolidPresenceOptions<I> = {},
): Presence<I, O> {
  const context = useSolidContext(ClientContext);
  const supabase = supabaseFor("usePresence", context, options.client);
  const caller = useCaller(context, options.client);
  const [members, setMembers] =
    createSignal<readonly PresenceMember<O>[]>(NO_MEMBERS);
  const [status, setStatus] = createSignal<SubscriptionStatus>("closed");
  const [join, setJoin] = createSignal<PresenceJoin<I> | undefined>();
  const name = createMemo(() => {
    const current = read(values);
    return current ? topic.topic(current) : null;
  });
  const state = createMemo(() => read(options.state), undefined, {
    equals: (a, b) => JSON.stringify(a) === JSON.stringify(b),
  });
  follow(
    createMemo(() => {
      const current = name();
      if (current === null || caller().status === "loading") return null;
      return JSON.stringify([current, caller().userId]);
    }),
    () => {
      const current = name();
      if (current === null) return;
      const joined = joinPresence(supabase, topic, current, {
        onStatus: (next) => {
          setStatus(next);
        },
        onPresence: (next) => {
          setMembers(next);
        },
      });
      if (!joined) return;
      setJoin(() => joined);
      return () => {
        setJoin(undefined);
        setMembers(NO_MEMBERS);
        setStatus("closed");
        joined.leave();
      };
    },
  );
  createEffect(() => {
    const joined = join();
    const value = state();
    joined?.sync(value);
  });
  return {
    get members() {
      return members();
    },
    get status() {
      return status();
    },
    track: (value) => join()?.track(value) ?? notJoined(),
    untrack: () => join()?.untrack() ?? notJoined(),
  };
}

export interface ActionHandle<I, T> extends ActionState<I, T> {
  /** Runs the action; resolves with its result. */
  readonly run: (input: I) => Promise<ActionResultOf<T>>;
  readonly reset: () => void;
}

/**
 * Calls a server action (`action()` from SolidStart, or a `bs.action()`)
 * from an event handler: tracks pending inputs and the last result, and
 * calls `onSuccess` or `onError`. The returned object's fields are reactive.
 *
 * ```tsx
 * const remove = useAction(removeMember);
 * <button disabled={remove.pending} onClick={() => remove.run({ userId })} />
 * ```
 */
export function useAction<I, T>(
  action: (input: I) => Promise<ActionResultOf<T>>,
  options: UseActionOptions<ActionInputOf<I>, T> = {},
): ActionHandle<ActionInputOf<I>, T> {
  // SAFETY: ActionInputOf<I> only drops FormData, which `I` accepts.
  const call = action as (
    input: ActionInputOf<I>,
  ) => Promise<ActionResultOf<T>>;
  const runner = createActionRunner(() => ({ action: call, options }));
  const [state, setState] = createSignal(runner.current());
  onCleanup(
    runner.subscribe(() => {
      setState(runner.current());
    }),
  );
  return {
    run: runner.run,
    reset: runner.reset,
    get pending() {
      return state().pending;
    },
    get pendingInputs() {
      return state().pendingInputs;
    },
    get pendingInput() {
      return state().pendingInput;
    },
    get data() {
      return state().data;
    },
    get error() {
      return state().error;
    },
  };
}
