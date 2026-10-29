"use client";

import type { ReactNode } from "react";

import {
  createContext,
  createElement,
  use,
  useContext,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import type { SupportView } from "../auth/support-view.ts";
import type { AuthSession } from "../auth/view.ts";
import type { AuthzVersionSource } from "../core/authz-topic.ts";
import type { AuthzRefreshClient } from "./authz-refresh.ts";

import { supportOf } from "../auth/support-view.ts";
import { startAuthzRefresh } from "./authz-refresh.ts";

type SessionValue = AuthSession | Promise<AuthSession>;

/** The session a provider holds, read with `useSyncExternalStore`. */
interface SessionStore {
  readonly get: () => SessionValue;
  readonly set: (value: SessionValue) => void;
  readonly subscribe: (listener: () => void) => () => void;
}

function createSessionStore(initial: SessionValue): SessionStore {
  let current = initial;
  const listeners = new Set<() => void>();

  return {
    get: () => current,
    set: (value) => {
      if (value === current) {
        return;
      }

      current = value;

      for (const listener of listeners) {
        listener();
      }
    },
    subscribe: (listener) => {
      listeners.add(listener);

      return () => {
        listeners.delete(listener);
      };
    },
  };
}

const SessionContext = createContext<SessionStore | null>(null);

export interface SessionProviderProps {
  /**
   * The server-verified session: `bsb.claims()`, unresolved when it's created
   * inside a `<Suspense>` boundary so the layout itself never waits for auth.
   */
  readonly session: AuthSession | Promise<AuthSession>;
  /**
   * A browser supabase-js client. With it the provider listens on the user's
   * private `authz:<uid>` topic (the sessions module's `authzVersions` option),
   * refreshes the token when the version changes and calls `onAuthzChange`.
   */
  readonly client?: AuthzRefreshClient;
  /**
   * Runs after the token refresh, such as `bsb.refreshSessionCache` followed by
   * `router.refresh()`. Other tabs run it too, without a second refresh.
   */
  readonly onAuthzChange?: () => unknown;
  /**
   * The `BroadcastChannel` that tells the app's other tabs, or `false` for
   * none. Defaults to `better-supabase:session`.
   */
  readonly channel?: string | false;
  /**
   * Where versions come from, for an authorization library with its own
   * channel. Defaults to `authz:<uid>` and `api.caller_authz_version()`.
   */
  readonly source?: AuthzVersionSource;
  /** The topic for a user id. Defaults to `authz:<uid>`. */
  readonly topic?: (userId: string) => string;
  /** The broadcast event. Defaults to `changed`. */
  readonly event?: string;
  readonly onError?: (error: Error) => void;
  readonly children?: ReactNode;
}

/**
 * The signed-in user's id, or `undefined` once the session resolves to
 * anonymous. `version` holds the token's `authz_ver`.
 */
function useUserId(
  store: SessionStore,
  version: { current: number | null },
): string | undefined {
  const value = useSyncExternalStore(store.subscribe, store.get, store.get);
  const [userId, setUserId] = useState<string | undefined>(undefined);

  useEffect(() => {
    let active = true;

    Promise.resolve(value)
      .then((session) => {
        if (active) {
          const user = session.kind === "user" ? session : undefined;
          version.current = user?.authzVersion ?? null;
          setUserId(user?.user.id);
        }
      })
      .catch(() => {
        // A rejected session renders through the Suspense error boundary.
      });

    return () => {
      active = false;
    };
  }, [value, version]);

  return userId;
}

/**
 * Shares the server-verified session with Client Components, and with a
 * `client` refreshes it when the database bumps the user's authorization
 * version.
 */
export function SessionProvider(props: SessionProviderProps): ReactNode {
  const [store] = useState(() => createSessionStore(props.session));
  const handlers = useRef(props);
  const version = useRef<number | null>(null);
  const userId = useUserId(store, version);
  const { client, source, topic, event } = props;
  const channel = props.channel ?? "better-supabase:session";

  useEffect(() => {
    handlers.current = props;
    store.set(props.session);
  });

  useEffect(() => {
    if (!client || userId === undefined) {
      return;
    }

    return startAuthzRefresh({
      client,
      userId,
      channel,
      ...(source ? { source } : {}),
      ...(topic ? { topic } : {}),
      ...(event ? { event } : {}),
      tokenVersion: () => version.current,
      onChange: () => handlers.current.onAuthzChange?.(),
      onError: (error) => handlers.current.onError?.(error),
    });
  }, [client, userId, channel, source, topic, event]);

  return createElement(
    SessionContext.Provider,
    { value: store },
    props.children,
  );
}

function useSessionValue(): SessionValue | undefined {
  const store = useContext(SessionContext);

  const subscribe = store?.subscribe ?? noSubscribe;
  const get = store?.get ?? noSession;

  return useSyncExternalStore(subscribe, get, get);
}

const noSubscribe = (): (() => void) => () => undefined;

const noSession = (): undefined => undefined;

/**
 * The session from the nearest `<SessionProvider>`. Suspends while the session
 * is a pending promise, so render it inside `<Suspense>`. `C` types the claims
 * (the output of `betterSupabase.claims(schema)`) and `P` the profile (the
 * output of `betterSupabase.userMetadata(schema)`); `createHooks().useSession`
 * infers both.
 */
export function useSession<C = unknown, P = unknown>(): AuthSession<C, P> {
  const value = useSessionValue();

  if (value === undefined) {
    throw new Error(
      "better-supabase: useSession() needs <SessionProvider session={...}>",
    );
  }

  // SAFETY: the provider receives `bsb.claims()` from the same `betterSupabase`, whose schemas fix `C` and `P`.
  return (value instanceof Promise ? use(value) : value) as AuthSession<C, P>;
}

/**
 * The support session the page renders in, for a "Viewing as" banner, or
 * `undefined` for a normal session. Needs `<SessionProvider>` like
 * `useSession`.
 */
export function useSupportSession(): SupportView | undefined {
  return supportOf(useSession());
}

/**
 * `useSupportSession()` that answers `undefined` outside a `<SessionProvider>`
 * instead of throwing.
 */
export function useOptionalSupportSession(): SupportView | undefined {
  const value = useSessionValue();

  if (value === undefined) {
    return undefined;
  }

  return supportOf(value instanceof Promise ? use(value) : value);
}
