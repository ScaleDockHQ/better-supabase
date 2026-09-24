import { describe, expect, it } from 'vitest';

import { resolveAuth } from '../auth/resolve.ts';
import { localAuth, signTestJwt } from './jwt.ts';

const SECRET = 'a-test-secret-that-is-at-least-32-characters';
const USER = '11111111-1111-4111-8111-111111111111';
const env = {
  url: 'https://abcdefghijklmnopqrst.supabase.co',
  publishableKey: 'sb_publishable_test',
  jwksUrl: new URL('https://abcdefghijklmnopqrst.supabase.co/jwks'),
};

const resolve = async (token: string) =>
  (
    await resolveAuth(
      new Request('https://api.test/', {
        headers: { authorization: `Bearer ${token}` },
      }),
      { env, resolvers: [localAuth(SECRET)], jwks: { keys: [] } },
    )
  ).auth;

describe('localAuth', () => {
  it('accepts signTestJwt tokens as users with their claims', async () => {
    const auth = await resolve(
      await signTestJwt(SECRET, { sub: USER, org_id: 'o1' }),
    );
    expect(auth).toMatchObject({
      kind: 'user',
      user: { id: USER, role: 'authenticated' },
      claims: { org_id: 'o1' },
    });
  });

  it('rejects expired tokens and ignores other signatures', async () => {
    expect(
      (await resolve(await signTestJwt(SECRET, { sub: USER, expiresIn: -10 })))
        .kind,
    ).toBe('invalid');
    expect(
      (await resolve(await signTestJwt(`${SECRET}-other`, { sub: USER }))).kind,
    ).toBe('invalid');
  });
});
