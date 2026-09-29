import 'server-only';
import { next } from '@/lib/supabase.server';

/**
 * The caller's customers. `next.cached()` queries with the user's token, so
 * RLS decides the rows; the private cache keeps them in this browser only,
 * for as long as the session view may be reused.
 */
export async function getCustomers() {
  'use cache: private';
  const { db } = await next.cached();
  return db.customers
    .findMany({
      select: ['id', 'name', 'status'],
      orderBy: { name: 'asc' },
      limit: 50,
    })
    .orThrow();
}
