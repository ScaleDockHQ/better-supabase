import type { JWTClaims, UserClaims } from '@supabase/server';

import type { DbError } from '../core/errors.ts';
import type { AuthState, InvalidReason } from './resolve.ts';

import { type Impersonator, impersonatorOf } from './impersonation.ts';
import { type Aal, aalOf, type AmrEntry, amrOf } from './mfa.ts';

/**
 * The verified caller as plain data: no token, no clients. Safe to return
 * from a `'use cache: private'` function and to pass to Client Components.
 */
export type AuthSession<C = unknown> =
  | {
      readonly kind: 'user';
      readonly user: UserClaims;
      /**
       * The verified JWT payload, including custom access token hook claims,
       * typed and validated by `sb.claims(schema)`.
       */
      readonly claims: JWTClaims & C;
      /** Seconds since epoch, from the token's `exp`. */
      readonly expiresAt: number | null;
      /** `aal2` once the user verified a second factor in this session. */
      readonly aal: Aal;
      /** How the user signed in (`password`, `totp`, `sso/saml`, ...). */
      readonly amr: readonly AmrEntry[];
      /** Set when an admin acts as this user (the `act` claim), for a banner. */
      readonly impersonator?: Impersonator;
    }
  | { readonly kind: 'service'; readonly keyName: string }
  | { readonly kind: 'anon'; readonly reason: AnonReason }
  | {
      readonly kind: 'invalid';
      readonly reason: InvalidReason;
      readonly error: DbError;
    };

type AnonReason = Extract<AuthState, { kind: 'anon' }>['reason'];

/** Drops the token from an `AuthState`, leaving only serializable fields. */
export function toSession<C>(auth: AuthState<C>): AuthSession<C> {
  switch (auth.kind) {
    case 'user': {
      const impersonator = impersonatorOf(auth.claims);
      return {
        kind: 'user',
        user: auth.user,
        claims: auth.claims,
        expiresAt: auth.expiresAt,
        aal: aalOf(auth.claims),
        amr: amrOf(auth.claims),
        ...(impersonator ? { impersonator } : {}),
      };
    }
    case 'service':
      return { kind: 'service', keyName: auth.keyName };
    case 'anon':
      return { kind: 'anon', reason: auth.reason };
    case 'invalid':
      return { kind: 'invalid', reason: auth.reason, error: auth.error };
    default: {
      const unhandled: never = auth;
      return unhandled;
    }
  }
}
