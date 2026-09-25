import type { JWTClaims, UserClaims } from '@supabase/server';

import type { DbError } from '../core/errors.ts';
import type { AuthState } from './resolve.ts';

/**
 * The verified caller as plain data: no token, no clients. Safe to return
 * from a `'use cache: private'` function and to pass to Client Components.
 */
export type AuthSession =
  | {
      readonly kind: 'user';
      readonly user: UserClaims;
      /** The verified JWT payload, including custom access token hook claims. */
      readonly claims: JWTClaims;
      /** Seconds since epoch, from the token's `exp`. */
      readonly expiresAt: number | null;
    }
  | { readonly kind: 'service'; readonly keyName: string }
  | { readonly kind: 'anon'; readonly reason: AnonReason }
  | { readonly kind: 'invalid'; readonly error: DbError };

type AnonReason = Extract<AuthState, { kind: 'anon' }>['reason'];

/** Drops the token from an `AuthState`, leaving only serializable fields. */
export function toSession(auth: AuthState): AuthSession {
  switch (auth.kind) {
    case 'user':
      return {
        kind: 'user',
        user: auth.user,
        claims: auth.claims,
        expiresAt: auth.expiresAt,
      };
    case 'service':
      return { kind: 'service', keyName: auth.keyName };
    case 'anon':
      return { kind: 'anon', reason: auth.reason };
    case 'invalid':
      return { kind: 'invalid', error: auth.error };
    default: {
      const unhandled: never = auth;
      return unhandled;
    }
  }
}
