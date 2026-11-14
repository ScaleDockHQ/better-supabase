import type { JwksStore } from "./jwks-cache.ts";

/**
 * The part of the Vercel Runtime Cache that `vercelRuntimeCache` calls, typed
 * structurally; `getCache()` from `@vercel/functions` returns it.
 */
export interface VercelRuntimeCache {
  get(key: string): Promise<unknown>;
  set(key: string, value: unknown, options?: { ttl?: number }): Promise<void>;
}

export interface VercelRuntimeCacheOptions {
  /** The cache namespace the key sets go in. Default: `better-supabase-jwks`. */
  readonly namespace?: string;
}

const DEFAULT_NAMESPACE = "better-supabase-jwks";

/**
 * A `JwksStore` on the Vercel Runtime Cache, so every function instance in a
 * region shares one fetched key set. Pass `getCache` from `@vercel/functions`;
 * it is called on first use, so the store can be created at module scope,
 * outside a request.
 */
export function vercelRuntimeCache(
  getCache: (options?: { namespace?: string }) => VercelRuntimeCache,
  options: VercelRuntimeCacheOptions = {},
): JwksStore {
  let cache: VercelRuntimeCache | undefined;

  const open = (): VercelRuntimeCache =>
    (cache ??= getCache({ namespace: options.namespace ?? DEFAULT_NAMESPACE }));

  return {
    get: async (key) => open().get(key),
    set: async (key, value, setOptions) => open().set(key, value, setOptions),
  };
}
