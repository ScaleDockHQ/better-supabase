import type { SupabaseClient } from '@supabase/supabase-js';

import { describe, expectTypeOf, it } from 'vitest';

import type { OffsetPage } from '../core/repository-types.ts';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineListQuery, type ListQuery } from './index.ts';

declare const client: SupabaseClient;
const sb = defineSupabase(schema);
const db = sb.connect(client);

describe('list types', () => {
  it('keeps sort and facet keys literal', async () => {
    const list = defineListQuery(sb, 'customers', {
      search: ['name'],
      facets: { status: 'status' },
      sorts: { name: { name: 'asc' }, newest: { createdAt: 'desc' } },
      defaultSort: 'newest',
    });
    const query = list.parse(undefined).value!;
    expectTypeOf(query).toEqualTypeOf<ListQuery<'name' | 'newest', 'status'>>();
    const page = await list
      .run(db, query, { select: ['id', 'name'] })
      .orThrow();
    expectTypeOf(page).toEqualTypeOf<
      OffsetPage<{ id: string; name: string }>
    >();
  });

  it('checks columns', () => {
    defineListQuery(sb, 'customers', {
      // @ts-expect-error search only takes text columns
      search: ['createdAtNumber'],
      sorts: { name: { name: 'asc' } },
      defaultSort: 'name',
    });
    defineListQuery(sb, 'customers', {
      sorts: { name: { name: 'asc' } },
      // @ts-expect-error default sort must be one of the sorts
      defaultSort: 'other',
    });
  });
});
