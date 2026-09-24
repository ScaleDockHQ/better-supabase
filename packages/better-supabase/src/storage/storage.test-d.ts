import { describe, expectTypeOf, it } from 'vitest';

import { defineBucket, type TemplateParams } from './index.ts';

describe('bucket types', () => {
  it('derives path values from the template', () => {
    const logos = defineBucket({
      id: 'logos',
      path: '{orgId}/{customerId}/logo/{version}.webp',
    });
    expectTypeOf<TemplateParams<'{a}/x/{b}.png'>>().toEqualTypeOf<'a' | 'b'>();
    expectTypeOf(logos.params).toEqualTypeOf<
      readonly ('orgId' | 'customerId' | 'version')[]
    >();
    logos.path({ orgId: 'o', customerId: 'c', version: 1 });
    // @ts-expect-error missing customerId
    logos.path({ orgId: 'o', version: 1 });
    // @ts-expect-error unknown placeholder
    logos.path({ orgId: 'o', customerId: 'c', version: 1, other: 'x' });
  });
});
