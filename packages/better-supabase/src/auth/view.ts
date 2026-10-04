import type { JWTClaims, UserClaims } from "@supabase/server";

import type { DbError } from "../core/errors.ts";
import type { AuthState, InvalidReason } from "./resolve.ts";

import {
  actorOf,
  delegationOf,
  type SessionActor,
  type SessionDelegation,
} from "./actor.ts";
import { type Impersonator, impersonatorOf } from "./impersonation.ts";
import { type Aal, aalOf, type AmrEntry, amrOf } from "./mfa.ts";

/**
 * The verified caller as plain data: no token, no clients. Safe to return
 * from a `'use cache: private'` function and to pass to Client Components.
 */
export type AuthSession<C = unknown, P = unknown> =
  | {
      readonly kind: "user";
      readonly user: UserClaims;
      /**
       * The verified JWT payload, including custom access token hook claims,
       * typed and validated by `betterSupabase.claims(schema)`.
       */
      readonly claims: JWTClaims & C;
      /** Seconds since epoch, from the token's `exp`. */
      readonly expiresAt: number | null;
      /**
       * `user_metadata` parsed by `betterSupabase.userMetadata(schema)`, for display.
       * Absent without a schema or when the metadata fails it. Users
       * write this data with `auth.updateUser()`: never base access on it.
       */
      readonly profile?: P;
      /** `aal2` once the user verified a second factor in this session. */
      readonly aal: Aal;
      /**
       * Signed in with `signInAnonymously()` (the `is_anonymous` claim). Guards
       * refuse these users unless `allow` lists `'anonymous'`.
       */
      readonly anonymous: boolean;
      /** How the user signed in (`password`, `totp`, `sso/saml`, ...). */
      readonly amr: readonly AmrEntry[];
      /**
       * Set when an admin acts as this user in a support session or an
       * impersonated session (`act.kind`), for a banner. Matches `actor`.
       */
      readonly impersonator?: Impersonator;
      /**
       * Who acts for the user: an OAuth client or agent (`client_id`, or an
       * `act` chain without `kind`), a support session or an impersonated
       * session, as PermDock's `actorOf` reads it.
       */
      readonly actor?: SessionActor;
      /**
       * The scopes the user granted an `oauth-client` actor, plus its `act`
       * chain. Never set for a support or impersonated session.
       */
      readonly delegation?: SessionDelegation;
    }
  | { readonly kind: "service"; readonly keyName: string }
  | { readonly kind: "anon"; readonly reason: AnonReason }
  | {
      readonly kind: "invalid";
      readonly reason: InvalidReason;
      readonly error: DbError;
    };

type AnonReason = Extract<AuthState, { kind: "anon" }>["reason"];

/** Whether the token belongs to an anonymous user (`signInAnonymously()`). */
export function isAnonymousUser(claims: Readonly<object>): boolean {
  return "is_anonymous" in claims && claims.is_anonymous === true;
}

/** Drops the token from an `AuthState`, leaving only serializable fields. */
export function toSession<C, P>(auth: AuthState<C, P>): AuthSession<C, P> {
  switch (auth.kind) {
    case "user": {
      const impersonator = impersonatorOf(auth.claims);
      const outcome = actorOf(auth.claims);
      const actor = outcome.ok ? outcome.actor : undefined;
      const client = actor?.kind === "oauth-client" ? actor : undefined;
      const scopes = client ? delegationOf(auth.claims)?.scopes : undefined;
      const delegation: SessionDelegation | undefined =
        client && (scopes || client.chain)
          ? {
              scopes: scopes ?? [],
              ...(client.chain ? { chain: client.chain } : {}),
            }
          : undefined;
      return {
        kind: "user",
        user: auth.user,
        claims: auth.claims,
        expiresAt: auth.expiresAt,
        ...(auth.profile === undefined ? {} : { profile: auth.profile }),
        aal: aalOf(auth.claims),
        anonymous: isAnonymousUser(auth.claims),
        amr: amrOf(auth.claims),
        ...(impersonator ? { impersonator } : {}),
        ...(actor ? { actor } : {}),
        ...(delegation ? { delegation } : {}),
      };
    }
    case "service":
      return { kind: "service", keyName: auth.keyName };
    case "anon":
      return { kind: "anon", reason: auth.reason };
    case "invalid":
      return { kind: "invalid", reason: auth.reason, error: auth.error };
    default: {
      const unhandled: never = auth;
      return unhandled;
    }
  }
}
