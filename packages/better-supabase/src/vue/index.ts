import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import {
  type App,
  computed,
  type ComputedRef,
  getCurrentInstance,
  getCurrentScope,
  inject,
  type InjectionKey,
  type MaybeRefOrGetter,
  onMounted,
  onScopeDispose,
  provide,
  readonly,
  type Ref,
  shallowRef,
  toValue,
  watch,
} from "vue";

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

interface Context {
  readonly client: ClientLike;
  readonly queryClient: QueryClient | undefined;
  readonly auth: Readonly<Ref<AuthSnapshot>>;
}

const CLIENT: InjectionKey<Context> = Symbol("better-supabase");
const SESSION: InjectionKey<MaybeRefOrGetter<AuthSession>> = Symbol(
  "better-supabase-session",
);

export interface BetterSupabaseVueOptions {
  /** better-supabase queries are reset when the user signs out or changes. */
  readonly queryClient?: QueryClient;
}

export interface BetterSupabasePlugin {
  install(app: App): void;
}

/**
 * The Vue plugin: provides the client to the composables and, with a
 * `queryClient`, resets better-supabase queries when the caller changes.
 *
 * ```ts
 * app.use(VueQueryPlugin, { queryClient }).use(betterSupabase(bs, { queryClient }));
 * ```
 */
export function betterSupabase(
  client: ClientLike,
  options: BetterSupabaseVueOptions = {},
): BetterSupabasePlugin {
  return {
    install(app) {
      const auth = shallowRef(client.auth.current());
      const stops = [
        client.auth.subscribe(() => {
          auth.value = client.auth.current();
        }),
      ];
      if (options.queryClient)
        stops.push(clearOnUserChange(options.queryClient, client.auth));
      app.onUnmount(() => {
        for (const stop of stops) stop();
      });
      app.provide(CLIENT, {
        client,
        queryClient: options.queryClient,
        auth: readonly(auth),
      });
    },
  };
}

function useContext(): Context {
  const context = inject(CLIENT, null);
  if (!context) {
    throw new Error(
      "better-supabase: install the plugin with app.use(betterSupabase(bs))",
    );
  }
  return context;
}

/**
 * Runs `start` on mount in a component, at once elsewhere (an effect
 * scope), and never during server rendering.
 */
function onClient(start: () => void): void {
  if (getCurrentInstance()) onMounted(start);
  else start();
}

/** The session state for UI: `loading`, `signed-out` or `signed-in` with the user and claims. */
export function useAuth(): Readonly<Ref<AuthSnapshot>> {
  return useContext().auth;
}

export function useSupabase(): SupabaseClient {
  return useContext().client.supabase;
}

/**
 * Shares a server-verified session (from `useAsyncData`, a loader or a
 * prop) with the components below.
 */
export function provideSession(session: MaybeRefOrGetter<AuthSession>): void {
  provide(SESSION, session);
}

/** The session from the nearest `provideSession()`. */
export function useSession<C = unknown, P = unknown>(): ComputedRef<
  AuthSession<C, P>
> {
  const session = inject(SESSION, null);
  if (session === null) {
    throw new Error(
      "better-supabase: useSession() needs provideSession(session) in a parent component",
    );
  }
  // SAFETY: provideSession receives `bs.session()` from the same
  // `betterSupabase`, whose schemas fix `C` and `P`.
  return computed(() => toValue(session) as AuthSession<C, P>);
}

/** The support session the page renders in, or `undefined` for a normal session. */
export function useSupportSession(): ComputedRef<SupportView | undefined> {
  const session = useSession();
  return computed(() => supportOf(session.value));
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

export interface BetterComposables<B extends ClientLike> {
  /** Repositories bound to the current session. */
  readonly useDb: () => B["db"];
  /** TanStack Query option factories: `useQuery(useQueries().customers.findMany())`. */
  readonly useQueries: () => B["queries"];
  readonly useSupabase: () => SupabaseClient;
  readonly useAuth: () => Readonly<Ref<AuthSnapshot>>;
  readonly useSession: () => ComputedRef<
    AuthSession<ClaimsOf<B>, ProfileOf<B>>
  >;
}

/**
 * Composables typed for your schema.
 *
 * ```ts
 * export const { useDb, useQueries, useAuth } = createBindings<typeof bs>();
 * ```
 */
export function createBindings<B extends ClientLike>(): BetterComposables<B> {
  return {
    useDb: () => useContext().client.db,
    useQueries: () => useContext().client.queries,
    useSupabase,
    useAuth,
    useSession: useSession<ClaimsOf<B>, ProfileOf<B>>,
  };
}

/** The caller a subscription runs as: the plugin's auth, or a plain client's. */
function useCaller(
  context: Context | null,
  client: SupabaseClient | undefined,
): Readonly<Ref<Caller>> {
  if (context && client === undefined)
    return computed(() => callerOf(context.auth.value));
  const supabase = client ?? context?.client.supabase;
  if (!supabase) throw new Error("better-supabase: no supabase client");
  const store = plainCaller(supabase);
  const caller = shallowRef(store.current());
  onClient(() => {
    const stop = store.subscribe(() => {
      caller.value = store.current();
    });
    onScopeDispose(stop);
  });
  return caller;
}

function supabaseFor(
  hook: string,
  context: Context | null,
  client: SupabaseClient | undefined,
): SupabaseClient {
  const supabase = client ?? context?.client.supabase;
  if (!supabase) {
    throw new Error(
      `better-supabase: ${hook} needs app.use(betterSupabase(bs)) or { client: supabase }`,
    );
  }
  return supabase;
}

/**
 * Subscribes to a topic while the component is mounted. A `null` value
 * pauses. It resubscribes when the topic values or the signed-in user change.
 *
 * ```ts
 * useBroadcast(customersTopic, () => ({ organizationId: org.value }), {}, { invalidate: ['customers'] });
 * ```
 */
export function useBroadcast<P extends string, E extends EventSchemas>(
  topic: Topic<P, E>,
  values: MaybeRefOrGetter<TemplateValues<P> | null | undefined>,
  handlers?: TopicHandlers<E>,
  options?: BroadcastOptions,
): Readonly<Ref<SubscriptionStatus>> {
  const context = inject(CLIENT, null);
  const supabase = supabaseFor("useBroadcast", context, options?.client);
  const queryClient = options?.queryClient ?? context?.queryClient;
  assertInvalidateClient("useBroadcast", options, queryClient);
  const caller = useCaller(context, options?.client);
  const status = shallowRef<SubscriptionStatus>("closed");
  const run = keyed();
  const key = computed(() => {
    const current = toValue(values);
    if (!current || caller.value.status === "loading") return null;
    return JSON.stringify([topic.topic(current), caller.value.userId]);
  });
  onClient(() => {
    watch(
      key,
      (next) => {
        run.update(next, () => {
          const current = toValue(values);
          if (!current) return;
          return startBroadcast({
            supabase,
            topic,
            name: topic.topic(current),
            latest: () => ({ handlers, options }),
            queryClient,
            onStatus: (next) => {
              status.value = next;
            },
          });
        });
      },
      { immediate: true },
    );
    onScopeDispose(run.stop);
  });
  return readonly(status);
}

/**
 * Keeps a query fresh: invalidates every cached query that read a table the
 * spec touches whenever one of them changes. A `null` spec pauses.
 *
 * ```ts
 * const spec = computed(() => betterSupabase.spec.customers.findMany({ where: { orgId: org.value } }));
 * useLiveQuery(spec);
 * ```
 */
export function useLiveQuery(
  spec: MaybeRefOrGetter<QuerySpec | null | undefined>,
  options: LiveQueryHookOptions = {},
): Readonly<Ref<SubscriptionStatus>> {
  const { client, queryClient, auth } = useContext();
  const status = shallowRef<SubscriptionStatus>("closed");
  const run = keyed();
  let joined: string | null = null;
  const key = computed(() => {
    const current = toValue(spec);
    if (current && !queryClient) {
      throw new Error(
        "better-supabase: useLiveQuery needs betterSupabase(bs, { queryClient })",
      );
    }
    return liveKey(client, current, auth.value, options);
  });
  onClient(() => {
    watch(
      key,
      (next) => {
        run.update(next, () => {
          const current = toValue(spec);
          if (!current || !queryClient || next === null) return;
          const resumed = joined === next;
          joined = next;
          return startLiveQuery({
            client,
            queryClient,
            spec: current,
            auth: auth.value,
            options,
            resumed,
            onStatus: (value) => {
              status.value = value;
            },
          });
        });
      },
      { immediate: true },
    );
    onScopeDispose(run.stop);
  });
  return readonly(status);
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
 * ```ts
 * const unread = useLiveCount(() => betterSupabase.spec.messages.count({ where: { read: false } }));
 * // {{ unread.count }}
 * ```
 */
export function useLiveCount(
  source: MaybeRefOrGetter<LiveCountSource>,
  options: LiveCountHookOptions = {},
): LiveCount {
  const { client, auth } = useContext();
  const status = shallowRef<SubscriptionStatus>("closed");
  const state = shallowRef<CountState>(NO_COUNT);
  const run = keyed();
  let joined: { key: string; at: number } | null = null;
  const parsed = computed(() => countSource(toValue(source), options));
  const key = computed(() =>
    liveKey(client, parsed.value.spec, auth.value, options),
  );
  onClient(() => {
    watch(
      key,
      (next) => {
        run.update(next, () => {
          const { spec, initial, seedAt } = parsed.value;
          if (!spec || next === null) return;
          const previous = joined?.key === next ? joined : null;
          joined = { key: next, at: previous?.at ?? seedAt ?? 0 };
          return startLiveCount({
            client,
            spec,
            key: next,
            auth: auth.value,
            options,
            immediate: initial === undefined && !previous,
            since: previous ? previous.at : seedAt,
            onState: (update) => {
              state.value = update(state.value);
              if (joined?.key === next)
                joined = { key: next, at: state.value.at };
            },
            onStatus: (value) => {
              status.value = value;
            },
          });
        });
      },
      { immediate: true },
    );
    onScopeDispose(run.stop);
  });
  const shown = computed(() =>
    shownCount(state.value, key.value, parsed.value),
  );
  return {
    get count() {
      return shown.value.count;
    },
    get status() {
      return status.value;
    },
    get error() {
      return shown.value.error;
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

export interface VuePresenceOptions<I> extends Omit<
  PresenceHookOptions<I>,
  "state"
> {
  readonly state?: MaybeRefOrGetter<I | null | undefined>;
}

const NO_MEMBERS: readonly never[] = [];

/**
 * Joins a presence topic while mounted and returns who is on it. A `null`
 * value pauses. The returned object's fields are reactive.
 *
 * ```ts
 * const room = usePresence(roomTopic, () => ({ roomId: id.value }), { state: () => ({ name: name.value }) });
 * ```
 */
export function usePresence<P extends string, I, O>(
  topic: PresenceTopic<P, I, O>,
  values: MaybeRefOrGetter<TemplateValues<P> | null | undefined>,
  options: VuePresenceOptions<I> = {},
): Presence<I, O> {
  const context = inject(CLIENT, null);
  const supabase = supabaseFor("usePresence", context, options.client);
  const caller = useCaller(context, options.client);
  const members = shallowRef<readonly PresenceMember<O>[]>(NO_MEMBERS);
  const status = shallowRef<SubscriptionStatus>("closed");
  let join: PresenceJoin<I> | undefined;
  const run = keyed();
  const key = computed(() => {
    const current = toValue(values);
    if (!current || caller.value.status === "loading") return null;
    return JSON.stringify([topic.topic(current), caller.value.userId]);
  });
  onClient(() => {
    watch(
      key,
      (next) => {
        run.update(next, () => {
          const current = toValue(values);
          if (!current) return;
          const joined = joinPresence(supabase, topic, topic.topic(current), {
            onStatus: (value) => {
              status.value = value;
            },
            onPresence: (value) => {
              members.value = value;
            },
          });
          if (!joined) return;
          join = joined;
          joined.sync(toValue(options.state));
          return () => {
            join = undefined;
            members.value = NO_MEMBERS;
            status.value = "closed";
            joined.leave();
          };
        });
      },
      { immediate: true },
    );
    watch(
      () => JSON.stringify(toValue(options.state)),
      () => join?.sync(toValue(options.state)),
    );
    onScopeDispose(run.stop);
  });
  return {
    get members() {
      return members.value;
    },
    get status() {
      return status.value;
    },
    track: (state) => join?.track(state) ?? notJoined(),
    untrack: () => join?.untrack() ?? notJoined(),
  };
}

export interface ActionHandle<I, T> extends ActionState<I, T> {
  /** Runs the action; resolves with its result. */
  readonly run: (input: I) => Promise<ActionResultOf<T>>;
  readonly reset: () => void;
}

/**
 * Calls a server action from an event handler: tracks pending inputs and
 * the last result, and calls `onSuccess` or `onError`. The returned
 * object's fields are reactive.
 *
 * ```ts
 * const remove = useAction(removeMember, { onError: (e) => toast.error(e.message) });
 * // <button :disabled="remove.pending" @click="remove.run({ userId })">
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
  const state = shallowRef(runner.current());
  const stop = runner.subscribe(() => {
    state.value = runner.current();
  });
  if (getCurrentScope()) onScopeDispose(stop);
  return {
    run: runner.run,
    reset: runner.reset,
    get pending() {
      return state.value.pending;
    },
    get pendingInputs() {
      return state.value.pendingInputs;
    },
    get pendingInput() {
      return state.value.pendingInput;
    },
    get data() {
      return state.value.data;
    },
    get error() {
      return state.value.error;
    },
  };
}
