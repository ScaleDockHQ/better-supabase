"use client";

import {
  createContext,
  createElement,
  type ReactNode,
  use,
  useContext,
} from "react";

import type { AuthSession } from "../auth/view.ts";

const SessionContext = createContext<Promise<AuthSession> | null>(null);

export interface SessionProviderProps {
  /**
   * An unresolved `bs.session()` promise, created inside a `<Suspense>`
   * boundary so the layout itself never waits for auth.
   */
  readonly sessionPromise: Promise<AuthSession>;
  readonly children?: ReactNode;
}

/** Shares the server-verified session with Client Components. */
export function SessionProvider(props: SessionProviderProps): ReactNode {
  return createElement(
    SessionContext.Provider,
    { value: props.sessionPromise },
    props.children,
  );
}

/**
 * The session from the nearest `<SessionProvider>`. Suspends until the
 * promise resolves, so render it inside `<Suspense>`. `C` types the claims
 * (the output of `betterSupabase.claims(schema)`) and `P` the profile (the output of
 * `betterSupabase.userMetadata(schema)`); `createHooks().useSession` infers both.
 */
export function useSession<C = unknown, P = unknown>(): AuthSession<C, P> {
  const promise = useContext(SessionContext);
  if (!promise) {
    throw new Error(
      "better-supabase: useSession() needs <SessionProvider sessionPromise={...}>",
    );
  }
  // SAFETY: the provider receives `bs.session()` from the same `betterSupabase`, whose schemas fix `C` and `P`.
  return use(promise) as AuthSession<C, P>;
}
