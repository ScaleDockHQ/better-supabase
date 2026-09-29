import { describe, expect, expectTypeOf, it } from 'vitest';

import type { AuthSession } from './view.ts';

import { type EntitlementKey, hasEntitlement } from './entitlements.ts';

const ACME = '00000000-0000-4000-8000-000000000001';
const GLOBEX = '00000000-0000-4000-8000-000000000002';

interface Claims {
  memberships: {
    tenant_id: string;
    roles: string[];
    entitlements: ('exports' | 'sso')[];
  }[];
}

const session = (claims: Claims): AuthSession<Claims> =>
  ({
    kind: 'user',
    user: { id: 'u1' },
    claims: { sub: 'u1', ...claims },
    expiresAt: null,
    aal: 'aal1',
    amr: [],
  }) as AuthSession<Claims>;

describe('hasEntitlement', () => {
  const user = session({
    memberships: [
      { tenant_id: ACME, roles: ['admin'], entitlements: ['exports'] },
      { tenant_id: GLOBEX, roles: ['member'], entitlements: [] },
    ],
  });

  it('checks the entitlement within one tenant', () => {
    expect(hasEntitlement(user, ACME, 'exports')).toBe(true);
    expect(hasEntitlement(user, ACME, 'sso')).toBe(false);
    expect(hasEntitlement(user, GLOBEX, 'exports')).toBe(false);
    expect(hasEntitlement(user, 'other', 'exports')).toBe(false);
  });

  it('is false without a user or a memberships claim', () => {
    expect(
      hasEntitlement({ kind: 'anon', reason: 'none' }, ACME, 'exports'),
    ).toBe(false);
    expect(
      hasEntitlement(session({} as Claims), ACME, 'exports' as never),
    ).toBe(false);
  });

  it('types keys from the claims schema', () => {
    expectTypeOf<EntitlementKey<Claims>>().toEqualTypeOf<'exports' | 'sso'>();
    expectTypeOf<EntitlementKey<unknown>>().toEqualTypeOf<string>();
    // @ts-expect-error: not an entitlement of the claims schema
    hasEntitlement(user, ACME, 'billing');
  });
});
