import { describe, expectTypeOf, it } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineSeed } from './seed.ts';

const sb = defineSupabase(schema);

describe('seed types', () => {
  it('keeps fixture names and checks rows against Insert types', () => {
    const seed = defineSeed(sb, {
      customers: {
        acme: {
          id: 'c1',
          organizationId: 'o1',
          name: 'Acme',
          status: 'active',
        },
      },
    });
    expectTypeOf(seed.rows.customers.acme.id).toEqualTypeOf<'c1'>();

    defineSeed(sb, {
      // @ts-expect-error name is required
      customers: { acme: { organizationId: 'o1' } },
    });
    defineSeed(sb, {
      customers: {
        acme: {
          organizationId: 'o1',
          name: 'Acme',
          // @ts-expect-error status is a union
          status: 'nope',
        },
      },
    });
    defineSeed(sb, {
      // @ts-expect-error unknown column
      customers: { acme: { organizationId: 'o1', name: 'Acme', nope: 1 } },
    });
    defineSeed(sb, {
      // @ts-expect-error unknown table
      nope: {},
    });
  });
});
