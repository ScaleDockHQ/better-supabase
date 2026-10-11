import { PostgrestClient } from "@supabase/postgrest-js";
import {
  type createClient as createClientType,
  type SupabaseClient,
} from "@supabase/supabase-js";

import type { AuthState } from "../auth/resolve.ts";
import type {
  PostgrestClientLike,
  PostgrestExecutorOptions,
} from "../core/postgrest-executor.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";
import type { LiteBackend } from "./lite.ts";
import type { ServerOptions } from "./server-types.ts";

const STATELESS = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false,
} as const;

/** What the server's Supabase clients are built from; `createClient` is injectable for tests. */
export interface ClientsInput {
  readonly options: ServerOptions;
  readonly env: () => BetterSupabaseEnv;
  readonly definitionExecutor: PostgrestExecutorOptions;
  readonly lite: LiteBackend | undefined;
  readonly createClient: typeof createClientType;
}

/** The Supabase and PostgREST clients of one server: shared service and anon clients, per-request user clients. */
export function createClients(input: ClientsInput): Clients {
  const { options, env, definitionExecutor, lite, createClient } = input;
  let adminClient: SupabaseClient | undefined;
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
  const sharedGlobal = {
    ...(customFetch ? { global: customFetch } : {}),
    ...dbOptions,
  };
  /** postgrest-js options a bare `PostgrestClient` takes; `timeout` is the executor's. */
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
  const serviceClient = (): SupabaseClient => {
    adminClient ??= createClient(env().url, secretKey(), {
      auth: STATELESS,
      ...sharedGlobal,
    });
    return adminClient;
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

  /** Clients for the primary share the service and anon clients; others don't. */
  const supabaseAt = (
    url: string,
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): SupabaseClient => {
    const custom = Object.keys(headers).length > 0;
    const global = custom
      ? { global: { headers, ...customFetch }, ...dbOptions }
      : sharedGlobal;
    const shared = !custom && url === env().url;
    switch (auth.kind) {
      case "user":
        // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
        return createClient(url, env().publishableKey, {
          accessToken: () => Promise.resolve(auth.token),
          ...global,
        });
      case "service":
        // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
        return shared
          ? serviceClient()
          : createClient(url, secretKey(), { auth: STATELESS, ...global });
      case "anon":
      case "invalid":
        if (!shared) {
          // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
          return createClient(url, env().publishableKey, {
            auth: STATELESS,
            ...global,
          });
        }
        anonClient ??= createClient(url, env().publishableKey, {
          auth: STATELESS,
          ...sharedGlobal,
        });
        return anonClient;
      case "apiKey":
        return apiKeyClient();
      default: {
        const exhaustive: never = auth;
        return exhaustive;
      }
    }
  };

  const supabaseFor = (
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
   * building Realtime, Storage and Auth clients per request; the shared
   * service and anon clients for the primary are built once anyway.
   */
  const restAt = (
    url: string,
    auth: AuthState,
    headers: Readonly<Record<string, string>> = {},
  ): PostgrestClientLike => {
    let key: string;
    let bearer: string;
    switch (auth.kind) {
      case "user":
        key = env().publishableKey;
        bearer = auth.token;
        break;
      case "service":
      case "anon":
      case "invalid":
        if (Object.keys(headers).length === 0 && url === env().url)
          return supabaseAt(url, auth, headers);
        key = auth.kind === "service" ? secretKey() : env().publishableKey;
        bearer = key;
        break;
      case "apiKey":
        return apiKeyClient();
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
    supabaseFor,
    restAt,
  };
}

export interface Clients {
  readonly executorOptions: PostgrestExecutorOptions;
  readonly tunedExecutor: boolean;
  readonly serviceClient: () => SupabaseClient;
  readonly readUrl: () => string | undefined;
  readonly apiKeyClient: () => never;
  readonly supabaseFor: (
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ) => SupabaseClient;
  readonly restAt: (
    url: string,
    auth: AuthState,
    headers?: Readonly<Record<string, string>>,
  ) => PostgrestClientLike;
}
