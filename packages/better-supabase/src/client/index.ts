import { createBrowserClient } from "@supabase/ssr";
import {
  createClient as createSupabaseClient,
  type SupabaseClient,
  type SupabaseClientOptions,
} from "@supabase/supabase-js";

import type { SessionEncoding } from "../auth/session.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterClient } from "./bind.ts";

import { EnvValidationError, parseEnv, type PublicEnv } from "../env/index.ts";
import { bindClient } from "./bind.ts";

export { bindClient } from "./bind.ts";
export type {
  AuthSnapshot,
  AuthUser,
  BetterClient,
  ClientAuth,
} from "./bind.ts";

export interface ClientOptions {
  /** URL and publishable key. Not needed when `client` is given. */
  readonly env?: PublicEnv;
  /**
   * Bring your own supabase-js client (custom storage). React Native apps
   * use `better-supabase/client/native`, which doesn't load `@supabase/ssr`.
   */
  readonly client?: SupabaseClient;
  /**
   * `cookies` (default) shares the session with the server through
   * `@supabase/ssr`; `local` keeps it in localStorage for SPAs without a server.
   */
  readonly storage?: "cookies" | "local";
  readonly cookies?: {
    /**
     * `tokens-only` keeps the user object out of the cookie (it lives in
     * `auth.userStorage`, localStorage by default), so cookies stay small.
     * Use the same value as the server's `encode`. Defaults to
     * `user-and-tokens`.
     */
    readonly encode?: SessionEncoding;
  };
  readonly auth?: {
    /** Where auth-js keeps the user object with `cookies.encode: 'tokens-only'`. */
    readonly userStorage?: UserStorage;
  };
}

type UserStorage = NonNullable<
  NonNullable<SupabaseClientOptions<"public">["auth"]>["userStorage"]
>;

function clientFor(options: ClientOptions): SupabaseClient {
  if (options.client) return options.client;
  if (!options.env)
    throw new TypeError(
      "createClient needs `env` ({ url, publishableKey }) or `client`",
    );
  const checked = parseEnv({
    SUPABASE_URL: options.env.url,
    SUPABASE_PUBLISHABLE_KEY: options.env.publishableKey,
  });
  if (!checked.ok) throw new EnvValidationError(checked.issues);
  const userStorage = options.auth?.userStorage;
  const auth = userStorage ? { auth: { userStorage } } : {};
  if (options.storage === "local")
    // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
    return createSupabaseClient(
      checked.env.url,
      checked.env.publishableKey,
      auth,
    );
  const encode = options.cookies?.encode;
  // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
  return createBrowserClient(checked.env.url, checked.env.publishableKey, {
    ...auth,
    ...(encode ? { cookies: { encode } } : {}),
  });
}

/**
 * The browser side: a supabase-js client, repositories that follow the
 * session, TanStack Query options and an auth store for UI state.
 *
 * ```ts
 * export const bs = createClient(betterSupabase, { env: { url, publishableKey } });
 * ```
 */
export function createClient<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: ClientOptions = {},
): BetterClient<M, F, E, C, P> {
  return bindClient(betterSupabase, clientFor(options));
}
