import type { AuthMode, JWTClaims, UserClaims } from "@supabase/server";

import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthState } from "../../auth/resolve.ts";

/** Entry contributing `ctx.auth`, the typed caller, from `ctx.bs`. */
export function withAuth<C, P>(): SingleKeyEntry<
  "auth",
  { readonly bs: { readonly auth: AuthState<C, P> } },
  AuthState<C, P>
> {
  return defineMiddleware<
    "auth",
    undefined,
    { readonly bs: { readonly auth: AuthState<C, P> } },
    AuthState<C, P>
  >({
    key: "auth",
    run: () => (_request, ctx) => Promise.resolve({ auth: ctx.bs.auth }),
  })();
}

/** `jwtClaims` as `withSupabase` contributes it: the verified token's payload, or `null`. */
export function jwtClaimsOf<C>(auth: AuthState<C>): (JWTClaims & C) | null {
  if (auth.kind === "user") return auth.claims;
  if (auth.kind === "apiKey") {
    // API key claims are synthesized, not parsed by the claims schema.
    // SAFETY: downstream entries (withPostgresClient, withOpenFeature) read only `sub` and `role`.
    return auth.claims as JWTClaims & C;
  }
  return null;
}

/** `userClaims` as `withSupabase` contributes it, or `null` without a user. */
export function userClaimsOf(auth: AuthState): UserClaims | null {
  return auth.kind === "user" ? auth.user : null;
}

/**
 * `authMode` as `withSupabase` names it: `user` for a verified user token
 * or a user's API key, `secret` for a secret key or an organization's API
 * key, `none` otherwise (no credentials, or ones a
 * guard refuses).
 */
export function authModeOf(auth: AuthState): AuthMode {
  switch (auth.kind) {
    case "user":
      return "user";
    case "service":
      return "secret";
    case "apiKey":
      return auth.userId ? "user" : "secret";
    case "anon":
    case "invalid":
      return "none";
    default: {
      const exhaustive: never = auth;
      return exhaustive;
    }
  }
}

/**
 * Entry contributing `ctx.jwtClaims` under the `withSupabase` key, so
 * `withPostgresClient` and `withOpenFeature` compose downstream.
 */
export function withJwtClaims<C, P>(): SingleKeyEntry<
  "jwtClaims",
  { readonly auth: AuthState<C, P> },
  (JWTClaims & C) | null
> {
  return defineMiddleware<
    "jwtClaims",
    undefined,
    { readonly auth: AuthState<C, P> },
    (JWTClaims & C) | null
  >({
    key: "jwtClaims",
    run: () => (_request, ctx) =>
      Promise.resolve({ jwtClaims: jwtClaimsOf(ctx.auth) }),
  })();
}

/** Entry contributing `ctx.userClaims` under the `withSupabase` key. */
export function withUserClaims<C, P>(): SingleKeyEntry<
  "userClaims",
  { readonly auth: AuthState<C, P> },
  UserClaims | null
> {
  return defineMiddleware<
    "userClaims",
    undefined,
    { readonly auth: AuthState<C, P> },
    UserClaims | null
  >({
    key: "userClaims",
    run: () => (_request, ctx) =>
      Promise.resolve({ userClaims: userClaimsOf(ctx.auth) }),
  })();
}

/** Entry contributing `ctx.authMode` under the `withSupabase` key. */
export function withAuthMode<C, P>(): SingleKeyEntry<
  "authMode",
  { readonly auth: AuthState<C, P> },
  AuthMode
> {
  return defineMiddleware<
    "authMode",
    undefined,
    { readonly auth: AuthState<C, P> },
    AuthMode
  >({
    key: "authMode",
    run: () => (_request, ctx) =>
      Promise.resolve({ authMode: authModeOf(ctx.auth) }),
  })();
}
