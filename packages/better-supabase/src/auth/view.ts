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
      /** Set when an admin acts as this user (the `act` claim), for a banner. */
      readonly impersonator?: Impersonator;
      /**
       * The OAuth client or agent acting for the user (`client_id`, or the
       * outermost `sub` of the `act` chain), as PermDock's `actorOf` reads it.
       */
      readonly actor?: SessionActor;
      /** The scopes the user granted `actor`, plus its `act` chain. Set only with `actor`. */
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
      const scopes = actor ? delegationOf(auth.claims)?.scopes : undefined;
      const delegation: SessionDelegation | undefined =
        actor && (scopes || actor.chain)
          ? {
              scopes: scopes ?? [],
              ...(actor.chain ? { chain: actor.chain } : {}),
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

/** A running support session as the target's view shows it, for a banner. */
export interface SupportView {
  readonly sessionId: string;
  /** The admin viewing the app. */
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason?: string;
  readonly readOnly: boolean;
  /** Seconds since epoch. */
  readonly expiresAt: number | null;
}

/** The support session behind `session`, or `undefined` outside one. */
export function supportOf(session: AuthSession): SupportView | undefined {
  if (session.kind !== "user") return;
  const { impersonator } = session;
  const sessionId = impersonator?.sessionId;
  if (!impersonator || !sessionId) return;
  return {
    sessionId,
    adminId: impersonator.id,
    targetUserId: session.user.id,
    ...(impersonator.reason ? { reason: impersonator.reason } : {}),
    readOnly: impersonator.readOnly ?? true,
    expiresAt: session.expiresAt,
  };
}
