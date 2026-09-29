import { describe, expect, it } from 'vitest';

import { aalOf, amrOf, checkAal } from './mfa.ts';

describe('mfa', () => {
  it('reads aal and amr from claims, skipping malformed entries', () => {
    expect(aalOf({ aal: 'aal2' })).toBe('aal2');
    expect(aalOf({ aal: 'aal3' })).toBe('aal1');
    expect(aalOf({})).toBe('aal1');
    expect(
      amrOf({
        amr: [
          { method: 'sso/saml', timestamp: 3, provider: 'okta-1' },
          { method: 'password' },
          'otp',
        ],
      }),
    ).toEqual([{ method: 'sso/saml', timestamp: 3, provider: 'okta-1' }]);
    expect(amrOf({ amr: 'password' })).toEqual([]);
  });

  it('only holds user sessions to the level', () => {
    expect(checkAal({ kind: 'service' }, 'aal2')).toBeUndefined();
    expect(checkAal({ kind: 'user', claims: {} }, 'aal1')).toBeUndefined();
    expect(checkAal({ kind: 'user', claims: {} }, 'aal2')).toMatchObject({
      kind: 'forbidden',
      status: 403,
      code: 'INSUFFICIENT_AAL',
      required: 'aal2',
    });
  });
});
