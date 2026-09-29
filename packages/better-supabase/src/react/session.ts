'use client';

import {
  createContext,
  createElement,
  type ReactNode,
  use,
  useContext,
} from 'react';

import type { AuthSession } from '../auth/view.ts';

const SessionContext = createContext<Promise<AuthSession> | null>(null);

export interface SessionProviderProps {
  /**
   * An unresolved `next.session()` promise, created inside a `<Suspense>`
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
 * (the output of `sb.claims(schema)`); `createHooks().useSession` infers it.
 */
export function useSession<C = unknown>(): AuthSession<C> {
  const promise = useContext(SessionContext);
  if (!promise) {
    throw new Error(
      'better-supabase: useSession() needs <SessionProvider sessionPromise={...}>',
    );
  }
  return use(promise) as AuthSession<C>;
}
