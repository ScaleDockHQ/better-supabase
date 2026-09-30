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
import type { AuthSnapshot, BrowserAuth } from "../client/index.ts";
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
import { liveCount, liveQuery } from "../realtime/live.ts";
import { useSession } from "./session.ts";

export { SessionProvider, useSession } from "./session.ts";
export type { SessionProviderProps } from "./session.ts";
export type { AuthSession } from "../auth/view.ts";
export type { Impersonator } from "../auth/impersonation.ts";
export { hasEntitlement } from "../auth/entitlements.ts";
export type { EntitlementKey, MembershipClaim } from "../auth/entitlements.ts";
export type { LiveCountSeed } from "../realtime/live.ts";

/** The parts of `createBrowser()` the provider needs. */
export interface BrowserLike {
  readonly sb: LiveSource;
  readonly supabase: SupabaseClient;
  readonly auth: BrowserAuth;
  readonly db: object;
  readonly queries: object;
}

interface ContextValue {
  readonly browser: BrowserLike;
  readonly queryClient: QueryClient | undefined;
}

const BrowserContext = createContext<ContextValue | null>(null);

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };

export interface BetterSupabaseProviderProps {
  readonly browser: BrowserLike;
  /** better-supabase queries are removed when the user signs out or changes. */
  readonly queryClient?: QueryClient;
  readonly children?: ReactNode;
}

/** Provides the browser client to the hooks. */
export function BetterSupabaseProvider(
  props: BetterSupabaseProviderProps,
): ReactNode {
  const { browser, queryClient } = props;
  const user = useRef<string | null | undefined>(undefined);

  useEffect(
    () =>
      browser.auth.subscribe(() => {
        const snapshot = browser.auth.current();
        if (snapshot.status === "loading") return;
        const id = snapshot.user?.id ?? null;
        if (user.current !== undefined && user.current !== id) {
          queryClient?.removeQueries({ queryKey: ["bs"] });
        }
        user.current = id;
      }),
    [browser, queryClient],
  );

  const value = useMemo(
    () => ({ browser, queryClient }),
    [browser, queryClient],
  );
  return createElement(BrowserContext.Provider, { value }, props.children);
}

function useBrowserContext(): ContextValue {
  const value = useContext(BrowserContext);
  if (!value) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider browser={browser}>",
    );
  }
  return value;
}

function useBrowser(): BrowserLike {
  return useBrowserContext().browser;
}

/** The session state for UI: `loading`, `signed-out` or `signed-in` with the user and claims. */
export function useAuth(): AuthSnapshot {
  const browser = useBrowser();
  return useSyncExternalStore(
    browser.auth.subscribe,
    browser.auth.current,
    () => LOADING,
  );
}

export function useSupabase(): SupabaseClient {
  return useBrowser().supabase;
}

export interface BetterHooks<B extends BrowserLike> {
  /** Repositories bound to the current session. Re-renders when the user changes. */
  readonly useDb: () => B["db"];
  /** TanStack Query option factories: `useQuery(useQueries().customers.findMany())`. */
  readonly useQueries: () => B["queries"];
  readonly useSupabase: () => SupabaseClient;
  readonly useAuth: () => AuthSnapshot;
  /** `useSession()` typed by the browser's `sb.claims(schema)` and `sb.userMetadata(schema)`. */
  readonly useSession: () => AuthSession<ClaimsOf<B>, ProfileOf<B>>;
}

/** The claims type of a browser's `sb.claims(schema)`, `unknown` without one. */
export type ClaimsOf<B extends BrowserLike> = B["sb"] extends {
  readonly claimsSchema: StandardSchemaV1<unknown, infer C> | undefined;
}
  ? C
  : unknown;

/** The profile type of a browser's `sb.userMetadata(schema)`, `unknown` without one. */
export type ProfileOf<B extends BrowserLike> = B["sb"] extends {
  readonly userMetadataSchema: StandardSchemaV1<unknown, infer P> | undefined;
}
  ? P
  : unknown;

/**
 * Hooks typed for your schema.
 *
 * ```ts
 * export const { useDb, useQueries, useAuth } = createHooks<typeof browser>();
 * ```
 */
export function createHooks<B extends BrowserLike>(): BetterHooks<B> {
  return {
    useDb() {
      const browser = useBrowser();
      useAuth();
      return browser.db;
    },
    useQueries() {
      const browser = useBrowser();
      useAuth();
      return browser.queries;
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
  const { browser, queryClient } = useBrowserContext();
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
    if (!name || auth.status === "loading") return undefined;
    const matched = topic.match(name);
    if (!matched) return undefined;
    const forward = (payload: unknown, message: TopicMessage) => {
      const current = latest.current;
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
      browser.supabase,
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
  }, [browser, topic, name, userId, auth.status, queryClient]);

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
 * const spec = sb.spec.customers.findMany({ include: { notes: true } });
 * const { data } = useQuery(q.$spec(spec));
 * useLiveQuery(spec);
 * ```
 */
export function useLiveQuery(
  spec: QuerySpec | null | undefined,
  options: LiveQueryHookOptions = {},
): SubscriptionStatus {
  const { browser, queryClient } = useBrowserContext();
  const auth = useAuth();
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  if (spec && !queryClient) {
    throw new Error(
      "better-supabase: useLiveQuery needs <BetterSupabaseProvider queryClient={...}>",
    );
  }
  const key = spec ? JSON.stringify(spec) : null;
  const tenant = options.tenant ?? claimedTenant(auth, browser.sb.meta);
  const userId = auth.user?.id ?? null;
  const debounceMs = options.debounceMs;

  useEffect(() => {
    if (!key || !queryClient || auth.status === "loading") return undefined;
    const live = liveQuery(
      browser.sb,
      browser.supabase,
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
  }, [browser, queryClient, key, tenant, userId, auth.status, debounceMs]);

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
 * channel rejoins. Takes a spec or a `next.liveCount()` seed; pass `null` to
 * pause. Doesn't need a `QueryClient`.
 *
 * ```tsx
 * const { count } = useLiveCount(seed); // seed = await next.liveCount(spec)
 * ```
 */
export function useLiveCount(
  source: QuerySpec<string, "count", number> | LiveCountSeed | null | undefined,
  options: LiveCountHookOptions = {},
): LiveCount {
  const { browser } = useBrowserContext();
  const auth = useAuth();
  const seed = source && "spec" in source ? source : undefined;
  const spec = seed ? seed.spec : (source as QuerySpec | null | undefined);
  const initial = seed?.count ?? options.initial;
  const [state, setState] = useState<{
    readonly key: string | null;
    readonly count: number | undefined;
    readonly error: DbError | undefined;
  }>({ key: null, count: undefined, error: undefined });
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const key = spec ? JSON.stringify(spec) : null;
  const tenant = options.tenant ?? claimedTenant(auth, browser.sb.meta);
  const userId = auth.user?.id ?? null;
  const debounceMs = options.debounceMs;
  const hasInitial = initial !== undefined;

  useEffect(() => {
    if (!key || auth.status === "loading") return undefined;
    const live = liveCount(
      browser.sb,
      browser.supabase,
      browser.db as CountRunner,
      JSON.parse(key) as QuerySpec<string, "count", number>,
      {
        immediate: !hasInitial,
        onCount: (count) => setState({ key, count, error: undefined }),
        onError: (error) =>
          setState((previous) => ({
            key,
            count: previous.key === key ? previous.count : undefined,
            error,
          })),
        onStatus: setStatus,
        ...(tenant === undefined ? {} : { tenant }),
        ...(debounceMs === undefined ? {} : { debounceMs }),
      },
    );
    return () => {
      void live.unsubscribe();
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId resubscribes with the new user's token.
  }, [browser, key, tenant, userId, auth.status, debounceMs, hasInitial]);

  const fresh = state.key === key;
  return {
    count: fresh && state.count !== undefined ? state.count : initial,
    status,
    error: fresh ? state.error : undefined,
  };
}
