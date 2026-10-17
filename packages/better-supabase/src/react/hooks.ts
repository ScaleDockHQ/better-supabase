"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import {
  createElement,
  type ReactNode,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import type { AuthSession } from "../auth/view.ts";
import type {
  BroadcastOptions,
  ClientLike,
  CountState,
  LiveCountHookOptions,
  LiveQueryHookOptions,
  ClaimsOf,
  ProfileOf,
} from "../bindings/client.ts";
import type { AuthSnapshot } from "../client/index.ts";
import type { DbError } from "../core/errors.ts";
import type { QuerySpec } from "../core/spec.ts";
import type {
  EventSchemas,
  SubscriptionStatus,
  TemplateValues,
  Topic,
  TopicHandlers,
} from "../realtime/index.ts";
import type { LiveCountSeed } from "../realtime/live.ts";

import {
  countSource,
  liveKey,
  NO_COUNT,
  shownCount,
  startBroadcast,
  startLiveCount,
  startLiveQuery,
} from "../bindings/client.ts";
import { sessionUserId, specKey } from "../bindings/keys.ts";
import { clearOnUserChange } from "../query/user-change.ts";
import { ClientContext, type ContextValue } from "./context.ts";
import { useSession } from "./session.ts";

export type { ClaimsOf, ProfileOf } from "../bindings/client.ts";

export type {
  BroadcastOptions,
  ClientLike,
  LiveCountHookOptions,
  LiveQueryHookOptions,
} from "../bindings/client.ts";

export { ClientContext } from "./context.ts";

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };

export interface BetterSupabaseProviderProps {
  readonly client: ClientLike;
  /** better-supabase queries are removed when the user signs out or changes. */
  readonly queryClient?: QueryClient;
  readonly children?: ReactNode;
}

/** Provides the better-supabase client to the hooks. */
export function BetterSupabaseProvider(
  props: BetterSupabaseProviderProps,
): ReactNode {
  const { client, queryClient } = props;

  useEffect(
    () =>
      queryClient ? clearOnUserChange(queryClient, client.auth) : undefined,
    [client, queryClient],
  );

  const value = useMemo(() => ({ client, queryClient }), [client, queryClient]);
  return createElement(ClientContext.Provider, { value }, props.children);
}

function useClientContext(): ContextValue {
  const value = useContext(ClientContext);
  if (!value) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider client={bs}>",
    );
  }
  return value;
}

function useClient(): ClientLike {
  return useClientContext().client;
}

/** The session state for UI: `loading`, `signed-out` or `signed-in` with the user and claims. */
export function useAuth(): AuthSnapshot {
  const client = useClient();
  return useSyncExternalStore(
    client.auth.subscribe,
    client.auth.current,
    () => LOADING,
  );
}

export function useSupabase(): SupabaseClient {
  return useClient().supabase;
}

export interface BetterHooks<B extends ClientLike> {
  /** Repositories bound to the current session. Re-renders when the user changes. */
  readonly useDb: () => B["db"];
  /** TanStack Query option factories: `useQuery(useQueries().customers.findMany())`. */
  readonly useQueries: () => B["queries"];
  readonly useSupabase: () => SupabaseClient;
  readonly useAuth: () => AuthSnapshot;
  /** `useSession()` typed by the client's `betterSupabase.claims(schema)` and `betterSupabase.userMetadata(schema)`. */
  readonly useSession: () => AuthSession<ClaimsOf<B>, ProfileOf<B>>;
}

/**
 * Hooks typed for your schema.
 *
 * ```ts
 * export const { useDb, useQueries, useAuth } = createHooks<typeof bs>();
 * ```
 */
export function createHooks<B extends ClientLike>(): BetterHooks<B> {
  return {
    useDb() {
      const client = useClient();
      useAuth();
      return client.db;
    },
    useQueries() {
      const client = useClient();
      useAuth();
      return client.queries;
    },
    useSupabase,
    useAuth,
    useSession: useSession<ClaimsOf<B>, ProfileOf<B>>,
  };
}

/**
 * Subscribes to a topic while mounted. Pass `null` values to pause. It
 * resubscribes when the topic or the signed-in user changes.
 *
 * ```ts
 * useBroadcast(customersTopic, organizationId ? { organizationId } : null, {}, { invalidate: ['customers'] });
 * ```
 */
export function useBroadcast<P extends string, E extends EventSchemas>(
  topic: Topic<P, E>,
  values: TemplateValues<P> | null | undefined,
  handlers?: TopicHandlers<E>,
  options?: BroadcastOptions,
): SubscriptionStatus {
  const context = useContext(ClientContext);
  const supabase = options?.client ?? context?.client.supabase;
  if (!supabase) {
    throw new Error(
      "better-supabase: useBroadcast needs <BetterSupabaseProvider client={bs}> or { client: supabase }",
    );
  }
  const queryClient = options?.queryClient ?? context?.queryClient;
  const auth = useBroadcastAuth(
    options?.client === undefined ? context?.client : undefined,
    supabase,
  );
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const latest = useRef({ handlers, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = { handlers, options };
  const name = values ? topic.topic(values) : null;
  const userId = auth.userId;
  const self = options?.self;
  if (options?.invalidate && !queryClient) {
    throw new Error(
      "better-supabase: useBroadcast({ invalidate }) needs <BetterSupabaseProvider queryClient={...}> or { queryClient }",
    );
  }

  useEffect(() => {
    if (!name || auth.status === "loading") return;
    return startBroadcast({
      supabase,
      topic,
      name,
      latest: () => latest.current,
      queryClient,
      onStatus: setStatus,
    });
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId resubscribes with the new user's token.
  }, [supabase, topic, name, userId, auth.status, queryClient, self]);

  return status;
}

const NO_AUTH = (): (() => void) => () => undefined;

/**
 * The user `useBroadcast` subscribes as: the provider's auth snapshot, or
 * for a plain supabase-js client, its auth state.
 */
export function useBroadcastAuth(
  client: ClientLike | undefined,
  supabase: SupabaseClient,
): { readonly status: AuthSnapshot["status"]; readonly userId: string | null } {
  const snapshot = useSyncExternalStore(
    client?.auth.subscribe ?? NO_AUTH,
    client?.auth.current ?? (() => LOADING),
    () => LOADING,
  );
  const [plain, setPlain] = useState<{
    readonly status: AuthSnapshot["status"];
    readonly userId: string | null;
  }>({ status: "loading", userId: null });
  useEffect(() => {
    if (client) return;
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setPlain({
        status: session ? "signed-in" : "signed-out",
        userId: session ? sessionUserId(session) : null,
      });
    });
    return () => {
      data.subscription.unsubscribe();
    };
  }, [client, supabase]);
  return client
    ? { status: snapshot.status, userId: snapshot.user?.id ?? null }
    : plain;
}

/**
 * The spec from the render whose key last changed, so effects keep the
 * original values (`bigint`, Temporal) and only rerun on a different query.
 */
function useHeldSpec<S extends QuerySpec>(
  spec: S | null | undefined,
): { readonly key: string | null; readonly spec: S | null } {
  const key = spec ? specKey(spec) : null;
  const [held, setHeld] = useState({ key, spec: spec ?? null });
  if (held.key === key) return held;
  const next = { key, spec: spec ?? null };
  setHeld(next);
  return next;
}

/**
 * Keeps a query fresh: invalidates every cached query that read a table the
 * spec touches whenever one of them changes. Pass `null` to pause. It
 * resubscribes when the spec, tenant or user changes.
 *
 * ```ts
 * const spec = betterSupabase.spec.customers.findMany({ include: { notes: true } });
 * const { data } = useQuery(q.$spec(spec));
 * useLiveQuery(spec);
 * ```
 */
export function useLiveQuery(
  spec: QuerySpec | null | undefined,
  options: LiveQueryHookOptions = {},
): SubscriptionStatus {
  const { client, queryClient } = useClientContext();
  const auth = useAuth();
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  if (spec && !queryClient) {
    throw new Error(
      "better-supabase: useLiveQuery needs <BetterSupabaseProvider queryClient={...}>",
    );
  }
  const held = useHeldSpec(spec);
  const joined = useRef<string | null>(null);
  const key = liveKey(client, held.spec, auth, options);
  const latest = useRef({ auth, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the key already restarts the effect on a change.
  latest.current = { auth, options };

  useEffect(() => {
    if (key === null || !held.spec || !queryClient) return;
    // A rejoin with the same spec (an <Activity> shown again) missed the
    // changes made while it was hidden.
    const resumed = joined.current === held.key;
    joined.current = held.key;
    return startLiveQuery({
      client,
      queryClient,
      spec: held.spec,
      auth: latest.current.auth,
      options: latest.current.options,
      resumed,
      onStatus: setStatus,
    });
  }, [client, queryClient, held, key]);

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
 * A count that stays current: refetches only the `count` spec (a HEAD
 * request) after each debounced change to a table it reads, and after the
 * channel rejoins. Takes a spec or a `bs.liveCount()` seed; pass `null` to
 * pause. Doesn't need a `QueryClient`.
 *
 * ```tsx
 * const { count } = useLiveCount(seed); // seed = await bs.liveCount(spec)
 * ```
 */
export function useLiveCount(
  source: QuerySpec<string, "count", number> | LiveCountSeed | null | undefined,
  options: LiveCountHookOptions = {},
): LiveCount {
  const { client } = useClientContext();
  const auth = useAuth();
  const parsed = countSource(source, options);
  const [state, setState] = useState<CountState>(NO_COUNT);
  const stateRef = useRef<CountState>(NO_COUNT);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const held = useHeldSpec(parsed.spec);
  const joined = useRef<{ key: string | null; at: number } | null>(null);
  const key = liveKey(client, held.spec, auth, options);
  const latest = useRef({ auth, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the key already restarts the effect on a change.
  latest.current = { auth, options };
  const hasInitial = parsed.initial !== undefined;
  const { seedAt } = parsed;

  useEffect(() => {
    if (key === null || !held.spec || held.key === null) return;
    const specKey = held.key;
    // A rejoin with the same spec (an <Activity> shown again) counts again
    // once joined: changes made while it was hidden were missed.
    const previous = joined.current?.key === specKey ? joined.current : null;
    joined.current = { key: specKey, at: previous?.at ?? seedAt ?? 0 };
    return startLiveCount({
      client,
      spec: held.spec,
      key: specKey,
      auth: latest.current.auth,
      options: latest.current.options,
      immediate: !hasInitial && !previous,
      since: previous ? previous.at : seedAt,
      onState: (update) => {
        const next = update(stateRef.current);
        stateRef.current = next;
        if (next.error === undefined && joined.current?.key === specKey)
          joined.current = { key: specKey, at: next.at };
        setState(next);
      },
      onStatus: setStatus,
    });
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- `key` holds the spec, tenant, user and debounce.
  }, [client, held.spec, held.key, key, hasInitial, seedAt]);

  const shown = shownCount(state, held.key, parsed);
  return { count: shown.count, status, error: shown.error };
}
