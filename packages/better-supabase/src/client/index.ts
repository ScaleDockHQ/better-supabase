import { createBrowserClient } from "@supabase/ssr";
import {
  createClient as createSupabaseClient,
  type SupabaseClient,
} from "@supabase/supabase-js";

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
}

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
  if (options.storage === "local")
    // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
    return createSupabaseClient(checked.env.url, checked.env.publishableKey);
  // oxlint-disable-next-line typescript/no-unsafe-return -- supabase-js infers `any` for the schema name without a Database type.
  return createBrowserClient(checked.env.url, checked.env.publishableKey);
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
