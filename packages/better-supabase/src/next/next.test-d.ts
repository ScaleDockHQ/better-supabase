import type { JWTClaims, UserClaims } from '@supabase/server';

import { describe, expectTypeOf, it } from 'vitest';

import type { AuthSession } from './index.ts';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { useSession } from '../react/index.ts';
import { createNext } from './index.ts';

const next = createNext(defineSupabase(schema));

describe('next.session', () => {
  it('returns the serializable session union', () => {
    expectTypeOf(next.session()).resolves.toEqualTypeOf<AuthSession>();
    expectTypeOf(useSession).returns.toEqualTypeOf<AuthSession>();
  });

  it('narrows to claims only for users and never exposes the token', () => {
    const session = {} as AuthSession;
    if (session.kind === 'user') {
      expectTypeOf(session.claims).toEqualTypeOf<JWTClaims>();
      expectTypeOf(session.user).toEqualTypeOf<UserClaims>();
      expectTypeOf(session).not.toHaveProperty('token');
    }
    expectTypeOf<AuthSession['kind']>().toEqualTypeOf<
      'user' | 'service' | 'anon' | 'invalid'
    >();
  });
});
