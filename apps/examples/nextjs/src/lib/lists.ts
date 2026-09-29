import { defineListQuery } from 'better-supabase/list';

import { sb } from './supabase';

/**
 * `/customers?q=&status=&sort=&page=`. With `facetCounts`, the page and the
 * per-status counts are two requests in one wave.
 */
export const customerList = defineListQuery(sb, 'customers', {
  search: ['name'],
  facets: { status: 'status' },
  sorts: {
    name: [{ name: 'asc' }, { id: 'asc' }],
    newest: [{ createdAt: 'desc' }, { id: 'asc' }],
  },
  defaultSort: 'name',
  pageSize: 50,
  facetCounts: true,
});
