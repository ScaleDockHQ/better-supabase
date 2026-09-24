import type { BetterHooks, BrowserLike } from './index.ts';

export {
  BetterSupabaseProvider,
  useAuth,
  useBroadcast,
  useLiveQuery,
  useSupabase,
} from './index.ts';
export type {
  BetterHooks,
  BetterSupabaseProviderProps,
  BroadcastOptions,
  BrowserLike,
  LiveQueryHookOptions,
} from './index.ts';

function clientOnly(name: string): () => never {
  return () => {
    throw new Error(
      `better-supabase: ${name}() runs in Client Components only. In Server Components use \`next.server()\` or \`db.$run(spec)\`.`,
    );
  };
}

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
