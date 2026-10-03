"use client";

import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/query-core";

import {
  createContext,
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
import type { AuthSnapshot, ClientAuth } from "../client/index.ts";
import type { DbError } from "../core/errors.ts";
import type { QuerySpec } from "../core/spec.ts";
import type {
  EventSchemas,
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
import type { SchemaMeta } from "../schema/types.ts";

import { claimAt, claimsOf, tenantClaimPaths } from "../core/claims.ts";
import { invalidateTables } from "../query/invalidate.ts";
import { clearOnUserChange } from "../query/user-change.ts";
import { liveCount, liveQuery } from "../realtime/live.ts";
import { useSession } from "./session.ts";

/** The parts of `createClient()` the provider needs. */
export interface ClientLike {
  readonly betterSupabase: LiveSource;
  readonly supabase: SupabaseClient;
  readonly auth: ClientAuth;
  readonly db: object;
  readonly queries: object;
}

interface ContextValue {
  readonly client: ClientLike;
  readonly queryClient: QueryClient | undefined;
}

const ClientContext = createContext<ContextValue | null>(null);

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

export interface BroadcastOptions extends Omit<SubscribeOptions, "onStatus"> {
  /**
   * Refetch after each message: table keys (every query that read one of
   * them), or a function returning query keys. Needs `queryClient` on the
   * provider.
   */
  readonly invalidate?:
    | readonly string[]
    | ((message: TopicMessage) => readonly (readonly unknown[])[]);
}

/**
 * Subscribes to a topic while mounted. Pass `null` values to pause. It
 * resubscribes when the topic or the signed-in user changes.
 *
 * ```ts
 * useBroadcast(customersTopic, orgId ? { orgId } : null, {}, { invalidate: ['customers'] });
 * ```
 */
export function useBroadcast<P extends string, E extends EventSchemas>(
  topic: Topic<P, E>,
  values: TemplateValues<P> | null | undefined,
  handlers?: TopicHandlers<E>,
  options?: BroadcastOptions,
): SubscriptionStatus {
  const { client, queryClient } = useClientContext();
  const auth = useAuth();
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const latest = useRef({ handlers, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = { handlers, options };
  const name = values ? topic.topic(values) : null;
  const userId = auth.user?.id ?? null;
  if (options?.invalidate && !queryClient) {
    throw new Error(
      "better-supabase: useBroadcast({ invalidate }) needs <BetterSupabaseProvider queryClient={...}>",
    );
  }

  useEffect(() => {
    if (!name || auth.status === "loading") return;
    const matched = topic.match(name);
    if (!matched) return;
    const forward = (payload: unknown, message: TopicMessage) => {
      const current = latest.current;
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
    const subscription = topic.subscribe(
      client.supabase,
      matched,
      { "*": forward },
      {
        ...(latest.current.options?.self === undefined
          ? {}
          : { self: latest.current.options.self }),
        onStatus: setStatus,
        onInvalid: (message, issues) =>
          latest.current.options?.onInvalid?.(message, issues),
      },
    );
    return () => {
      void subscription.unsubscribe();
      setStatus("closed");
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId resubscribes with the new user's token.
  }, [client, topic, name, userId, auth.status, queryClient]);

  return status;
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

function claimedTenant(
  auth: AuthSnapshot,
  meta: SchemaMeta,
): string | undefined {
  if (auth.status !== "signed-in") return undefined;
  for (const path of tenantClaimPaths(claimsOf(meta).tenant)) {
    const value = claimAt(auth.claims, path);
    if (value !== undefined) return value;
  }
  return undefined;
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
  const key = spec ? JSON.stringify(spec) : null;
  const tenant =
    options.tenant ?? claimedTenant(auth, client.betterSupabase.meta);
  const userId = auth.user?.id ?? null;
  const debounceMs = options.debounceMs;

  useEffect(() => {
    if (!key || !queryClient || auth.status === "loading") return;
    // SAFETY: key is JSON.stringify of the QuerySpec this hook received.
    const live = liveQuery(
      client.betterSupabase,
      client.supabase,
      JSON.parse(key) as QuerySpec,
      {
        onChange: (tables) => void invalidateTables(queryClient, tables),
        onStatus: setStatus,
        ...(tenant === undefined ? {} : { tenant }),
        ...(debounceMs === undefined ? {} : { debounceMs }),
      },
    );
    return () => {
      void live.unsubscribe();
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId resubscribes with the new user's token.
  }, [client, queryClient, key, tenant, userId, auth.status, debounceMs]);

  return status;
}

export interface LiveCountHookOptions extends LiveQueryHookOptions {
  /** The count to show before the first fetch, e.g. from the server. */
  readonly initial?: number;
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
  const seed = source && "spec" in source ? source : undefined;
  // SAFETY: source is a seed with a spec or a plain spec, and the in check
  // ruled out the seed.
  const spec = seed ? seed.spec : (source as QuerySpec | null | undefined);
  const initial = seed?.count ?? options.initial;
  const [state, setState] = useState<{
    readonly key: string | null;
    readonly count: number | undefined;
    readonly error: DbError | undefined;
  }>({ key: null, count: undefined, error: undefined });
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const key = spec ? JSON.stringify(spec) : null;
  const tenant =
    options.tenant ?? claimedTenant(auth, client.betterSupabase.meta);
  const userId = auth.user?.id ?? null;
  const debounceMs = options.debounceMs;
  const hasInitial = initial !== undefined;

  useEffect(() => {
    if (!key || auth.status === "loading") return;
    // SAFETY: the client db runs count specs, and key is JSON.stringify of a count spec.
    const live = liveCount(
      client.betterSupabase,
      client.supabase,
      client.db as CountRunner,
      JSON.parse(key) as QuerySpec<string, "count", number>,
      {
        immediate: !hasInitial,
        onCount: (count) => {
          setState({ key, count, error: undefined });
        },
        onError: (error) => {
          setState((previous) => ({
            key,
            count: previous.key === key ? previous.count : undefined,
            error,
          }));
        },
        onStatus: setStatus,
        ...(tenant === undefined ? {} : { tenant }),
        ...(debounceMs === undefined ? {} : { debounceMs }),
      },
    );
    return () => {
      void live.unsubscribe();
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId resubscribes with the new user's token.
  }, [client, key, tenant, userId, auth.status, debounceMs, hasInitial]);

  const fresh = state.key === key;
  return {
    count: fresh && state.count !== undefined ? state.count : initial,
    status,
    error: fresh ? state.error : undefined,
  };
}
