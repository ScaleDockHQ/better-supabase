import type { JWTClaims } from '@supabase/server';

import type { AuthResolver } from '../auth/resolve.ts';

import { dbError } from '../core/errors.ts';

export interface TestJwtClaims {
  readonly sub: string;
  readonly role?: string;
  readonly email?: string;
  readonly aal?: 'aal1' | 'aal2';
  readonly expiresIn?: number;
  readonly [claim: string]: unknown;
}

const encoder = new TextEncoder();

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

/**
 * Signs an HS256 access token the local Supabase stack accepts. Test-only:
 * production tokens come from Supabase Auth.
 */
export async function signTestJwt(
  secret: string,
  claims: TestJwtClaims,
): Promise<string> {
  const { expiresIn = 3600, ...rest } = claims;
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    aud: 'authenticated',
    role: 'authenticated',
    aal: 'aal1',
    iat: now,
    exp: now + expiresIn,
    ...rest,
  };
  const header = base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = base64url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(`${header}.${body}`),
  );
  return `${header}.${body}.${base64url(new Uint8Array(signature))}`;
}

function base64urlDecode(input: string): Uint8Array<ArrayBuffer> {
  const binary = atob(input.replaceAll('-', '+').replaceAll('_', '/'));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/**
 * Accepts `signTestJwt` tokens as users, for API servers tested against the
 * local stack: `createServer(sb, { auth: { resolvers: [localAuth(secret)] } })`.
 * Tokens that are not HS256-signed with `secret` fall through. Test-only.
 */
export function localAuth(secret: string): AuthResolver {
  const key = crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  return {
    name: 'local-hs256',
    async resolve(request) {
      const token = /^Bearer (.+)$/i.exec(
        request.headers.get('authorization') ?? '',
      )?.[1];
      const [header, body, signature] = token?.split('.') ?? [];
      if (!token || !header || !body || !signature) return undefined;
      const valid = await crypto.subtle
        .verify(
          'HMAC',
          await key,
          base64urlDecode(signature),
          encoder.encode(`${header}.${body}`),
        )
        .catch(() => false);
      if (!valid) return undefined;
      const claims = JSON.parse(
        new TextDecoder().decode(base64urlDecode(body)),
      ) as JWTClaims;
      if (typeof claims.exp === 'number' && claims.exp * 1000 < Date.now()) {
        return {
          kind: 'invalid',
          error: dbError('unauthorized', 'The token has expired'),
        };
      }
      return {
        kind: 'user',
        token,
        claims,
        user: {
          id: claims.sub,
          ...(typeof claims.role === 'string' ? { role: claims.role } : {}),
          ...(typeof claims.email === 'string' ? { email: claims.email } : {}),
        },
        source: 'bearer',
        expiresAt: typeof claims.exp === 'number' ? claims.exp : null,
      };
    },
  };
}

export interface TestSigner {
  /** Public JWKS; pass as `jwks` to `resolveAuth` / `createServer({ auth: { jwks } })`. */
  readonly jwks: { readonly keys: readonly JsonWebKey[] };
  sign(claims: TestJwtClaims): Promise<string>;
}

/** An in-memory ES256 key pair that signs tokens like Supabase Auth's asymmetric keys. */
export async function createTestSigner(): Promise<TestSigner> {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );
  const kid = crypto.randomUUID();
  const publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return {
    jwks: {
      keys: [{ ...publicJwk, kid, alg: 'ES256', use: 'sig' } as JsonWebKey],
    },
    async sign(claims) {
      const { expiresIn = 3600, ...rest } = claims;
      const now = Math.floor(Date.now() / 1000);
      const payload = {
        aud: 'authenticated',
        role: 'authenticated',
        aal: 'aal1',
        iat: now,
        exp: now + expiresIn,
        ...rest,
      };
      const header = base64url(
        JSON.stringify({ alg: 'ES256', typ: 'JWT', kid }),
      );
      const body = base64url(JSON.stringify(payload));
      const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        pair.privateKey,
        encoder.encode(`${header}.${body}`),
      );
      return `${header}.${body}.${base64url(new Uint8Array(signature))}`;
    },
  };
}
