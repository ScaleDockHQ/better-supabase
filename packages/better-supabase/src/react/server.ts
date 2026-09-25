import type { AuthSession } from '../auth/view.ts';
import type { BetterHooks, BrowserLike } from './index.ts';

export {
  BetterSupabaseProvider,
  useAuth,
  useBroadcast,
  useLiveQuery,
  useSupabase,
} from './index.ts';
// Kept external by tsdown so it stays a `'use client'` module: a Server
// Component layout can render it and pass the session promise across.
export { SessionProvider } from './session.js';
export type {
  BetterHooks,
  BetterSupabaseProviderProps,
  BroadcastOptions,
  BrowserLike,
  LiveQueryHookOptions,
} from './index.ts';
export type { SessionProviderProps } from './session.ts';
export type { AuthSession } from '../auth/view.ts';

function clientOnly(name: string): () => never {
  return () => {
    throw new Error(
      `better-supabase: ${name}() runs in Client Components only. In Server Components use \`next.server()\` or \`db.$run(spec)\`.`,
    );
  };
}

/** The `react-server` build of `useSession`: await `next.session()` instead. */
export const useSession: () => AuthSession = clientOnly('useSession');

/**
 * The `react-server` build of `createHooks`: importing a module that creates
 * hooks is safe on the server, calling a hook there throws.
 */
export function createHooks<B extends BrowserLike>(): BetterHooks<B> {
  return {
    useDb: clientOnly('useDb'),
    useQueries: clientOnly('useQueries'),
    useSupabase: clientOnly('useSupabase'),
    useAuth: clientOnly('useAuth'),
  };
}
