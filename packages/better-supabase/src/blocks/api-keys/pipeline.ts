import type { Entry, SingleKeyEntry } from "@supabase/middleware";
import type { AuthMode, JWTClaims, UserClaims } from "@supabase/server";

import { defineComposite, defineMiddleware } from "@supabase/middleware";

import type { AuthState } from "../../auth/resolve.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { ApiKeyResolverOptions } from "./api-keys.ts";

import {
  withAuthMode,
  withJwtClaims,
  withUserClaims,
} from "../../auth/claims.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { apiKeyResolver } from "./api-keys.ts";

export interface WithApiKeyOptions<F extends object = Record<never, never>>
  extends ApiKeyResolverOptions<F>, BlockProblemOptions {}

/** The API key a request verified with, as `withApiKey` puts it on `ctx.auth`. */
export type ApiKeyAuth = Extract<AuthState, { readonly kind: "apiKey" }>;

/** The keys `withApiKey` puts on `ctx`. */
export interface ApiKeyContributions {
  readonly auth: ApiKeyAuth;
  /**
   * The key's claims (`sub`, `role: authenticated`, `api_key`), for
   * `withPostgresClient`.
   */
  readonly jwtClaims: JWTClaims | null;
  readonly userClaims: UserClaims | null;
  readonly authMode: AuthMode;
}

function withApiKeyAuth<F extends object>(
  options: WithApiKeyOptions<F>,
): SingleKeyEntry<"auth", Record<never, never>, ApiKeyAuth> {
  const resolver = apiKeyResolver(options);

  return defineMiddleware<"auth", undefined, Record<never, never>, ApiKeyAuth>({
    key: "auth",
    run: () => async (request) => {
      const instance = new URL(request.url).pathname;
      const state = await resolver.resolve(request);

      if (state?.kind === "apiKey") {
        return { auth: state };
      }

      return problemResponse(
        state?.kind === "invalid"
          ? state.error
          : dbError("unauthorized", "An API key is required", {
              code: "API_KEY_REQUIRED",
            }),
        {
          instance,
          format: options.problem,
          headers: { "www-authenticate": 'Bearer realm="api"' },
        },
      );
    },
  })();
}

/**
 * A `@supabase/server` pipeline entry for routes that take API keys
 * (`x-api-key`, or `Authorization: Bearer` with a key): it verifies the key
 * with `keys.verify`, answers a missing, invalid or rate-limited key with
 * Problem Details, and contributes `ctx.auth` and the `withSupabase` keys
 * (`jwtClaims`, `userClaims`, `authMode`) from the key's claims, so
 * `withPostgresClient` and `withBetterPostgres` run queries as the key.
 *
 * ```ts
 * pipeline([withApiKey({ keys }), withPostgresClient(), withBetterPostgres(betterSupabase)()], (req, ctx) => ...)
 * ```
 */
export function withApiKey<F extends object = Record<never, never>>(
  options: WithApiKeyOptions<F>,
): Entry<ApiKeyContributions> {
  return defineComposite({
    build: () =>
      [
        withApiKeyAuth(options),
        withJwtClaims<unknown, unknown>(),
        withUserClaims<unknown, unknown>(),
        withAuthMode<unknown, unknown>(),
      ] as const,
  })();
}
