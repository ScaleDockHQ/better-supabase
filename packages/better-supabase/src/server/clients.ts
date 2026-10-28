import type {
  SupabaseClient,
  SupabaseClientOptions,
} from "@supabase/supabase-js";

import { PostgrestClient } from "@supabase/postgrest-js";
import { createAdminClient, createContextClient } from "@supabase/server/core";

import type { AuthState } from "../auth/resolve.ts";
import type {
  PostgrestClientLike,
  PostgrestExecutorOptions,
} from "../core/postgrest-executor.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";
import type { LiteBackend } from "./lite.ts";
import type { ServerOptions } from "./server-types.ts";

/**
 * Clients never verify a token; a key set here keeps `@supabase/server` from
 * reading the JWKS variables on every client it builds.
 */
const NO_KEYS = Object.freeze({ keys: [] });

/** What the server's Supabase clients are built from. */
export interface ClientsInput {
  readonly options: ServerOptions;
  readonly env: () => BetterSupabaseEnv;
  readonly definitionExecutor: PostgrestExecutorOptions;
  readonly lite: LiteBackend | undefined;
}

/**
 * A client built on its first property read, `in` check or key enumeration,
 * like the one `withSupabaseAdminClient` puts on its context. Methods are bound
 * to the built client, so its private fields stay reachable.
 */
export function lazyClient<T extends object>(build: () => T): T {
  let client: T | undefined;
  const instance = (): T => (client ??= build());

  // SAFETY: every trap answers from the built client, so the proxy is a T.
  return new Proxy({} as T, {
    get: (_target, property) => {
      const target = instance();
      // SAFETY: the proxy only forwards reads of the built client's members.
      const value: unknown = target[property as keyof T];

      if (typeof value !== "function") {
        return value;
      }

      const bound: unknown = value.bind(target);

      return bound;
    },
    set: (_target, property, value) => Reflect.set(instance(), property, value),
    has: (_target, property) => Reflect.has(instance(), property),
    getPrototypeOf: () => Reflect.getPrototypeOf(instance()),
    ownKeys: () => Reflect.ownKeys(instance()),
    getOwnPropertyDescriptor: (_target, property) =>
      Reflect.getOwnPropertyDescriptor(instance(), property),
  });
}

/**
 * The Supabase and PostgREST clients of one server: a shared admin client and
 * anon client for the primary, per-request context clients for users.
 * supabase-js clients come from `createContextClient` and `createAdminClient`
 * (`@supabase/server/core`); queries skip them for a bare `PostgrestClient`.
 */
export function createClients(input: ClientsInput): Clients {
  const { options, env, definitionExecutor, lite } = input;
  let anonClient: SupabaseClient | undefined;

  const secretKey = (): string => {
    const key = env().secretKey;

    if (!key) {
      throw new TypeError("admin() needs SUPABASE_SECRET_KEY; it is not set");
    }

    return key;
  };

  const customFetch = options.fetch ? { fetch: options.fetch } : undefined;

  const urlLengthLimit =
    options.db?.urlLengthLimit ?? definitionExecutor.urlLengthLimit;

  const db = {
    ...(options.db?.timeout === undefined
      ? {}
      : { timeout: options.db.timeout }),
    ...(options.db?.retry === undefined ? {} : { retry: options.db.retry }),
    ...(urlLengthLimit === undefined ? {} : { urlLengthLimit }),
  };

  const dbOptions = Object.keys(db).length > 0 ? { db } : {};

  /**
   * Postgrest-js options a bare `PostgrestClient` takes; `timeout` is the
   * executor's.
   */
  const restOptions = {
    ...(db.retry === undefined ? {} : { retry: db.retry }),
    ...(urlLengthLimit === undefined ? {} : { urlLengthLimit }),
  };

  const rpcUnavailable = lite?.rpcUnavailable;

  const executorOptions = {
    ...definitionExecutor,
    ...(urlLengthLimit === undefined ? {} : { urlLengthLimit }),
    ...(db.timeout === undefined ? {} : { timeout: db.timeout }),
    ...(db.retry === undefined ? {} : { retry: db.retry }),
    ...(rpcUnavailable === undefined ? {} : { rpcUnavailable }),
  };

  /** Set when `db` options or the backend need an executor built with them. */
  const tunedExecutor =
    options.db !== undefined || rpcUnavailable !== undefined;

  /** Supabase-js options shared by every client, plus request headers. */
  const supabaseOptions = (
    headers: Readonly<Record<string, string>>,
    token?: string,
  ): SupabaseClientOptions<string> => ({
    ...(customFetch || Object.keys(headers).length > 0
      ? { global: { headers: { ...headers }, ...customFetch } }
      : {}),
    // Realtime reads the token through this callback, not the headers.
    ...(token === undefined
      ? {}
      : { realtime: { accessToken: () => Promise.resolve(token) } }),
    ...dbOptions,
  });

  const contextClientAt = (
    url: string,
    headers: Readonly<Record<string, string>>,
    token?: string,
  ): SupabaseClient =>
    createContextClient({
      ...(token === undefined ? {} : { auth: { token } }),
      env: {
        url,
        publishableKeys: { default: env().publishableKey },
        jwks: NO_KEYS,
      },
      supabaseOptions: supabaseOptions(headers, token),
    });

  const adminClientAt = (
    url: string,
    headers: Readonly<Record<string, string>>,
  ): SupabaseClient =>
    createAdminClient({
      env: { url, secretKeys: { default: secretKey() }, jwks: NO_KEYS },
      supabaseOptions: supabaseOptions(headers),
    });

  const sharedAdmin = lazyClient(() => adminClientAt(env().url, {}));

  /**
   * The shared admin client, built on first use. The key is checked now, so a
   * missing `SUPABASE_SECRET_KEY` throws where the client is asked for.
   */
  const serviceClient = (): SupabaseClient => {
    secretKey();

    return sharedAdmin;
  };

  const readUrl = (): string | undefined =>
    options.readUrl === false
      ? undefined
      : (options.readUrl?.replace(/\/+$/, "") ?? env().readUrl);

  const apiKeyClient = (): never => {
    throw new TypeError(
      "ctx.supabase and ctx.db.$client are not available for an API key: ctx.db and ctx.sql run over direct Postgres with the key's claims",
    );
  };

  /** Clients for the primary share the admin and anon clients; others don't. */
  const supabaseAt = (
    url: string,
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): SupabaseClient => {
    const shared = Object.keys(headers).length === 0 && url === env().url;

    switch (auth.kind) {
      case "user": {
        return contextClientAt(url, headers, auth.token);
      }

      case "secret": {
        return shared ? serviceClient() : adminClientAt(url, headers);
      }

      case "none":
      case "invalid": {
        if (!shared) {
          return contextClientAt(url, headers);
        }

        anonClient ??= contextClientAt(url, headers);

        return anonClient;
      }

      case "apiKey": {
        return apiKeyClient();
      }

      default: {
        const exhaustive: never = auth;

        return exhaustive;
      }
    }
  };

  const contextClient = (
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): SupabaseClient => supabaseAt(env().url, auth, headers);

  const restUrls = new Map<string, string>();

  const restUrl = (url: string): string => {
    let rest = restUrls.get(url);

    if (rest === undefined) {
      rest = new URL("rest/v1", url.endsWith("/") ? url : `${url}/`).href;
      restUrls.set(url, rest);
    }

    return rest;
  };

  /**
   * The client queries run on. Requests need only PostgREST, so they skip
   * building Realtime, Storage and Auth clients per request; the shared service
   * and anon clients for the primary are built once anyway.
   */
  const restAt = (
    url: string,
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): PostgrestClientLike => {
    let key: string;
    let bearer: string;

    switch (auth.kind) {
      case "user": {
        key = env().publishableKey;
        bearer = auth.token;
        break;
      }

      case "secret":
      case "none":
      case "invalid": {
        if (Object.keys(headers).length === 0 && url === env().url) {
          return supabaseAt(url, auth, headers);
        }

        key = auth.kind === "secret" ? secretKey() : env().publishableKey;
        bearer = key;
        break;
      }

      case "apiKey": {
        return apiKeyClient();
      }

      default: {
        const exhaustive: never = auth;

        return exhaustive;
      }
    }

    return new PostgrestClient(restUrl(url), {
      headers: { ...headers, apikey: key, Authorization: `Bearer ${bearer}` },
      ...customFetch,
      ...restOptions,
    });
  };

  return {
    executorOptions,
    tunedExecutor,
    serviceClient,
    readUrl,
    apiKeyClient,
    contextClient,
    restAt,
  };
}

export interface Clients {
  readonly executorOptions: PostgrestExecutorOptions;
  readonly tunedExecutor: boolean;
  readonly serviceClient: () => SupabaseClient;
  readonly readUrl: () => string | undefined;
  readonly apiKeyClient: () => never;
  readonly contextClient: (
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ) => SupabaseClient;
  readonly restAt: (
    url: string,
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ) => PostgrestClientLike;
}
