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
   * A supabase-js client to subscribe with, for apps without
   * `<BetterSupabaseProvider>`. It resubscribes when the client's user
   * changes. Defaults to the provider's client.
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
  if (options?.invalidate && !queryClient) {
    throw new Error(
      "better-supabase: useBroadcast({ invalidate }) needs <BetterSupabaseProvider queryClient={...}> or { queryClient }",
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
      supabase,
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
  }, [supabase, topic, name, userId, auth.status, queryClient]);

  return status;
}

const NO_AUTH = (): (() => void) => () => undefined;

/**
 * The user `useBroadcast` subscribes as: the provider's auth snapshot, or
 * for a plain supabase-js client, its auth state.
 */
function useBroadcastAuth(
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
        userId: session?.user.id ?? null,
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

function specKey(spec: QuerySpec): string {
  return JSON.stringify(spec, (_key, value: unknown) =>
    typeof value === "bigint" ? { $bigint: value.toString() } : value,
  );
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
  const tenant =
    options.tenant ?? claimedTenant(auth, client.betterSupabase.meta);
  const userId = auth.user?.id ?? null;
  const debounceMs = options.debounceMs;

  useEffect(() => {
    if (!held.spec || !queryClient || auth.status === "loading") return;
    // A rejoin with the same spec (an <Activity> shown again) missed the
    // changes made while it was hidden.
    const resumed = joined.current === held.key;
    joined.current = held.key;
    const live = liveQuery(client.betterSupabase, client.supabase, held.spec, {
      onChange: (tables) => void invalidateTables(queryClient, tables),
      onStatus: setStatus,
      ...(tenant === undefined ? {} : { tenant }),
      ...(userId === null ? {} : { user: userId }),
      ...(debounceMs === undefined ? {} : { debounceMs }),
    });
    if (resumed) {
      live.ready.then(
        () => void invalidateTables(queryClient, live.tables),
        () => undefined,
      );
    }
    return () => {
      void live.unsubscribe();
    };
  }, [client, queryClient, held, tenant, userId, auth.status, debounceMs]);

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
    readonly at: number;
    readonly error: DbError | undefined;
  }>({ key: null, count: undefined, at: 0, error: undefined });
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  // SAFETY: a seed holds a count spec, and a plain source is one.
  const held = useHeldSpec(
    spec as QuerySpec<string, "count", number> | null | undefined,
  );
  const joined = useRef<{ key: string | null; at: number } | null>(null);
  const tenant =
    options.tenant ?? claimedTenant(auth, client.betterSupabase.meta);
  const userId = auth.user?.id ?? null;
  const debounceMs = options.debounceMs;
  const hasInitial = initial !== undefined;
  const seedAt = seed?.at;

  useEffect(() => {
    if (!held.spec || auth.status === "loading") return;
    const key = held.key;
    // A rejoin with the same spec (an <Activity> shown again) counts again
    // once joined: changes made while it was hidden were missed.
    const previous = joined.current?.key === key ? joined.current : null;
    joined.current = { key, at: previous?.at ?? seedAt ?? 0 };
    const since = previous ? previous.at : seedAt;
    // SAFETY: the client db runs count specs.
    const live = liveCount(
      client.betterSupabase,
      client.supabase,
      client.db as CountRunner,
      held.spec,
      {
        immediate: !hasInitial && !previous,
        ...(since === undefined ? {} : { since }),
        onCount: (count) => {
          const at = Date.now();
          if (joined.current?.key === key) joined.current = { key, at };
          setState({ key, count, at, error: undefined });
        },
        onError: (error) => {
          setState((last) => ({
            key,
            count: last.key === key ? last.count : undefined,
            at: last.key === key ? last.at : 0,
            error,
          }));
        },
        onStatus: setStatus,
        ...(tenant === undefined ? {} : { tenant }),
        ...(userId === null ? {} : { user: userId }),
        ...(debounceMs === undefined ? {} : { debounceMs }),
      },
    );
    return () => {
      void live.unsubscribe();
    };
  }, [
    client,
    held,
    tenant,
    userId,
    auth.status,
    debounceMs,
    hasInitial,
    seedAt,
  ]);

  const fresh = state.key === held.key;
  // A seed rendered after the last client count (a router.refresh()) wins.
  const seedNewer =
    seedAt !== undefined && seed?.count !== null && seedAt > state.at;
  return {
    count:
      fresh && state.count !== undefined && !seedNewer ? state.count : initial,
    status,
    error: fresh ? state.error : undefined,
  };
}
