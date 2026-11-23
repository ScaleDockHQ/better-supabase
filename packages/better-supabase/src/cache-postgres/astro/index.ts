import type { SupabaseClient } from "@supabase/supabase-js";

import { createClient } from "@supabase/supabase-js";

import type { PostgresCacheStore, PostgresCacheTables } from "../store-core.ts";

import { postgresCacheNames } from "../names.ts";
import { createCacheStore, isStore, restBackend } from "../store-core.ts";

/** The part of Astro's `CacheProvider` this provider implements. */
export interface AstroCacheProviderLike {
  name: string;
  onRequest(
    context: {
      request: Request;
      url: URL;
      waitUntil?: ((promise: Promise<unknown>) => void) | undefined;
      logger: { warn(message: string): void };
    },
    next: () => Promise<Response>,
  ): Promise<Response>;
  invalidate(options: {
    path?: string;
    tags?: string | string[];
  }): Promise<void>;
}

export interface AstroPostgresCacheConfig extends PostgresCacheTables {
  /** Name of the env variable with the project URL. Default: `SUPABASE_URL`. */
  readonly urlEnv?: string;
  /**
   * Env variable with the service role key. Default:
   * `SUPABASE_SERVICE_ROLE_KEY`.
   */
  readonly keyEnv?: string;
}

export interface AstroPostgresCacheOptions extends PostgresCacheTables {
  /** A service role client, or a store to share with other code. */
  readonly client: SupabaseClient | PostgresCacheStore;
}

function directive(header: string | null, name: string): number {
  const match = new RegExp(`(?:^|,)\\s*${name}=(\\d+)`, "i").exec(header ?? "");

  return match ? Number(match[1]) : 0;
}

function tagsOf(header: string | null): string[] {
  return (header ?? "")
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean);
}

/** The key: origin and path with the query sorted. */
function keyOf(url: URL): string {
  const params = new URLSearchParams(url.searchParams);
  params.sort();
  const query = params.toString();

  return `astro:${url.origin}${url.pathname}${query === "" ? "" : `?${query}`}`;
}

/**
 * An Astro `CacheProvider` over Postgres. A GET response whose
 * `CDN-Cache-Control` has `max-age` is stored with its `Cache-Tag` tags and
 * served until `max-age` (and, stale, until `stale-while-revalidate`) runs out;
 * `invalidate({ tags })` and `invalidate({ path })` take effect on every
 * instance. Responses with `Set-Cookie` or `Vary: Cookie` are never stored. A
 * database error is a miss, never a failed request.
 */
export function astroPostgresCache(
  options: AstroPostgresCacheOptions,
): AstroCacheProviderLike {
  const { client } = options;

  const store: PostgresCacheStore = isStore(client)
    ? client
    : createCacheStore(
        restBackend(client, postgresCacheNames(options)),
        options,
      );

  const render = async (
    key: string,
    url: URL,
    context: Parameters<AstroCacheProviderLike["onRequest"]>[0],
    next: () => Promise<Response>,
    label: string,
  ): Promise<Response> => {
    const response = await next();
    const header = response.headers.get("CDN-Cache-Control");
    const maxAge = directive(header, "max-age");
    const swr = directive(header, "stale-while-revalidate");
    const vary = response.headers.get("Vary")?.toLowerCase() ?? "";

    if (
      maxAge <= 0 ||
      response.headers.has("set-cookie") ||
      vary.includes("cookie") ||
      vary.trim() === "*" ||
      (response.body === null && response.status >= 300)
    ) {
      return response;
    }

    const copy = response.clone();
    const body = new Uint8Array(await copy.arrayBuffer());
    const now = Date.now();
    const headers = [...copy.headers];

    const written = await store.set({
      key,
      value: body,
      tags: tagsOf(response.headers.get("Cache-Tag")),
      storedAt: now,
      expiresAt: now + (maxAge + swr) * 1000,
      path: `${url.pathname}${url.search}`,
      meta: { status: response.status, headers, maxAge, swr },
    });

    if (!written.ok) {
      context.logger.warn(written.error.message);
    }

    response.headers.set("X-Astro-Cache", label);

    return response;
  };

  return {
    name: "better-supabase-postgres",

    async onRequest(context, next) {
      if (context.request.method !== "GET") {
        return next();
      }

      const url = new URL(context.request.url);
      const key = keyOf(url);
      const found = await store.lookup(key);

      if (!found.ok) {
        context.logger.warn(found.error.message);

        return next();
      }

      const row = found.data?.entry;

      if (!row) {
        return render(key, url, context, next, "MISS");
      }

      // SAFETY: `render` below wrote `meta` with these fields.
      const meta = row.meta as {
        status: number;
        headers: [string, string][];
        maxAge: number;
      };

      const fresh = Date.now() < row.storedAt + meta.maxAge * 1000;

      const response = new Response(new Blob([row.value]), {
        status: meta.status,
        headers: meta.headers,
      });

      response.headers.set("X-Astro-Cache", fresh ? "HIT" : "STALE");

      if (!fresh) {
        // Without `waitUntil` the refresh runs unawaited on a long-lived
        // server.
        const refresh = render(key, url, context, next, "MISS").catch(
          (error: unknown) => {
            context.logger.warn(String(error));
          },
        );

        context.waitUntil?.(refresh);
      }

      return response;
    },

    async invalidate(invalidateOptions) {
      if (invalidateOptions.path !== undefined) {
        const deleted = await store.deletePath(invalidateOptions.path);

        if (!deleted.ok) {
          throw new Error(deleted.error.message);
        }
      }

      if (invalidateOptions.tags !== undefined) {
        const tags = Array.isArray(invalidateOptions.tags)
          ? invalidateOptions.tags
          : [invalidateOptions.tags];

        const marked = await store.markTags(tags);

        if (!marked.ok) {
          throw new Error(marked.error.message);
        }
      }
    },
  };
}

function envOf(name: string): string | undefined {
  // SAFETY: `process` exists on Node and Bun and not on workers, where the
  // variable is then unset and the provider throws a clear error.
  const host = globalThis as { process?: { env?: Record<string, string> } };

  return host.process?.env?.[name];
}

/**
 * The default export Astro loads for `cache: { provider: { entrypoint:
 * "better-supabase/cache-postgres/astro" } }`. It reads the project URL and the
 * service role key from the env variables named in `config`, on the first
 * request.
 */
// oxlint-disable-next-line import/no-default-export -- Astro loads a cache provider from the default export of its entrypoint (1 finding).
export default function astroPostgresCacheProvider(
  config?: AstroPostgresCacheConfig,
): AstroCacheProviderLike {
  let inner: AstroCacheProviderLike | undefined;

  const provider = (): AstroCacheProviderLike => {
    if (inner) {
      return inner;
    }

    const url = envOf(config?.urlEnv ?? "SUPABASE_URL");
    const key = envOf(config?.keyEnv ?? "SUPABASE_SERVICE_ROLE_KEY");

    if (!url || !key) {
      throw new TypeError(
        "The Postgres Astro cache needs the project URL and the service role key in the env",
      );
    }

    inner = astroPostgresCache({
      ...config,
      client: createClient(url, key, { auth: { persistSession: false } }),
    });

    return inner;
  };

  return {
    name: "better-supabase-postgres",
    onRequest: (context, next) => provider().onRequest(context, next),
    invalidate: (options) => provider().invalidate(options),
  };
}
