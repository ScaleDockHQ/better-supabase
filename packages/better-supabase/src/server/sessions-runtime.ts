import { getEnv } from "@supabase/middleware";

import type { AuthResolution, VerifiedUser } from "../auth/resolve.ts";
import type { SessionEncoding } from "../auth/session.ts";
import type { SessionMemo } from "../auth/snapshot.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { BetterSupabaseEnv, EnvSource } from "../env/index.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { LiteBackend } from "./lite.ts";
import type { ResolveRequestOptions, ServerOptions } from "./server-types.ts";

import { prefetchJwks, resolveAuth } from "../auth/resolve.ts";
import { processSessionMemo } from "../auth/snapshot.ts";
import { loadEnv } from "../env/index.ts";
import { liteBackend } from "./lite.ts";
import { defaultPrefetchJwks } from "./respond.ts";
import { countVerifications } from "./verify-count.ts";

/** The environment as `getEnv` resolves it, one variable at a time. */
const RUNTIME_ENV: EnvSource = new Proxy<EnvSource>(
  {},
  {
    get: (_target, key) => (typeof key === "string" ? getEnv(key) : undefined),
  },
);

/**
 * `options.env` as given when it is loaded already, parsed when it is a
 * variable map (never merged with the runtime's), else the runtime's.
 */
function envOf(env: ServerOptions["env"]): BetterSupabaseEnv {
  if (env === undefined) {
    return loadEnv(RUNTIME_ENV);
  }

  return isLoadedEnv(env) ? env : loadEnv(env);
}

/**
 * An `EnvSource` holds only strings, so a `URL` in `jwksUrl` means a loaded
 * env.
 */
function isLoadedEnv(
  env: BetterSupabaseEnv | EnvSource,
): env is BetterSupabaseEnv {
  return env.jwksUrl instanceof URL;
}

/**
 * What a server's session side needs: the environment, the verified-token memo
 * and `resolve`. `createServer` and `createProxy` both build it, so a page and
 * the proxy keep one JWKS cache and one session memo (ADR 0116 and 0595), and
 * the proxy bundle carries no repository, query builder or account code.
 */
/** What `sessionsRuntime` returns. */
export interface SessionsRuntime<C, P> {
  readonly env: () => BetterSupabaseEnv;
  readonly lite: LiteBackend | undefined;
  /** The one verified-token memo; `undefined` with `sessions: false`. */
  readonly verifiedTokens: SessionMemo<VerifiedUser> | undefined;
  readonly resolve: (
    request: Request,
    resolveOptions?: ResolveRequestOptions & {
      readonly encode?: SessionEncoding;
    },
  ) => Promise<AuthResolution<C, P>>;
}

export function sessionsRuntime<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  V extends AuthzVersionCache,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: ServerOptions<V>,
): SessionsRuntime<C, P> {
  let loaded: BetterSupabaseEnv | undefined;

  const env = (): BetterSupabaseEnv => (loaded ??= envOf(options.env));

  const lite = liteBackend(options, env);

  if (
    lite === undefined &&
    (options.prefetchJwks ?? defaultPrefetchJwks()) &&
    options.auth?.jwks === undefined
  ) {
    try {
      void prefetchJwks({ ...options.auth, env: env() });
    } catch {
      // No environment yet (a build step): the first request loads it.
    }
  }

  /** The one verified-token memo: the proxy, contexts and `getClaims` share it. */
  const verifiedTokens =
    options.sessions === false
      ? undefined
      : processSessionMemo<VerifiedUser>(
          (user) => user.expiresAt,
          options.sessions,
        );

  const resolve = async (
    request: Request,
    resolveOptions: ResolveRequestOptions & {
      readonly encode?: SessionEncoding;
    } = {},
  ): Promise<AuthResolution<C, P>> => {
    const claims = options.auth?.claims ?? betterSupabase.claimsSchema;
    const { endedSession } = resolveOptions;
    const userMetadata = betterSupabase.userMetadataSchema;

    const counted = countVerifications(resolveOptions.onVerify);

    const resolved = await resolveAuth(request, {
      logger: betterSupabase.events.logger,
      ...(verifiedTokens ? { memo: verifiedTokens } : {}),
      ...(lite ? lite.auth() : options.auth),
      ...(claims ? { claims } : {}),
      ...(userMetadata ? { userMetadata } : {}),
      env: env(),
      ...(resolveOptions.refresh === undefined
        ? {}
        : { refresh: resolveOptions.refresh }),
      ...(resolveOptions.cookies === undefined
        ? {}
        : { cookies: resolveOptions.cookies }),
      ...(resolveOptions.verifySession ? { verifySession: true } : {}),
      ...(endedSession ? { endedSession } : {}),
      ...(resolveOptions.leeway === undefined
        ? {}
        : { leeway: resolveOptions.leeway }),
      ...(resolveOptions.onTiming ? { onTiming: resolveOptions.onTiming } : {}),
      onVerify: counted.onVerify,
      ...(resolveOptions.encode === undefined
        ? {}
        : {
            cookie: { ...options.auth?.cookie, encode: resolveOptions.encode },
          }),
      onRefresh: (event) => {
        options.auth?.onRefresh?.(event);
        betterSupabase.events.emit("refresh", event);
      },
    });

    // The claims schema's output is merged into every verified user's claims,
    // and the userMetadata schema's output is the profile.
    // SAFETY: the resolver ran the claims and userMetadata schemas, so resolved
    // has their output types.
    const resolution = resolved as AuthResolution<C, P>;

    if (betterSupabase.events.has("auth")) {
      const { auth } = resolution;
      betterSupabase.events.emit("auth", {
        verifications: counted.count(),
        source:
          auth.kind === "user"
            ? auth.source === "cookie"
              ? "cookie"
              : "bearer"
            : auth.kind === "secret" || auth.kind === "apiKey"
              ? "bearer"
              : "none",
        ok: auth.kind !== "invalid",
        ...(auth.kind === "user"
          ? { userId: auth.user.id, rawSource: auth.source }
          : {}),
        ...(auth.kind === "none" || auth.kind === "invalid"
          ? { reason: auth.reason }
          : {}),
      });
    }

    return resolution;
  };

  return { env, lite, verifiedTokens, resolve };
}
