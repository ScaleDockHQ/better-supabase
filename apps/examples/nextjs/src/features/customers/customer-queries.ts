import 'server-only';
import { cacheLife } from 'next/cache';

import { next } from '@/lib/supabase.server';

/**
 * The caller's customers. `next.server()` queries with the user's token, so
 * RLS decides the rows; the private cache keeps them in this browser only.
 */
export async function getCustomers() {
  'use cache: private';
  cacheLife('minutes');
  const { db } = await next.server();
  return db.customers
    .findMany({
      select: ['id', 'name', 'status'],
      orderBy: { name: 'asc' },
      limit: 50,
    })
    .orThrow();
}
