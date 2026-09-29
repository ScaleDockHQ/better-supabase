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
      // Counted and maxed in the database, in the same request.
      include: {
        _count: { notes: true },
        _max: { notes: { createdAt: true } },
      },
      orderBy: { name: 'asc' },
      limit: 50,
    })
    .orThrow();
}

/** Customers per status, as one grouped `count()`. */
export async function getStatusCounts() {
  'use cache: private';
  const { db } = await next.cached();
  return db.customers
    .aggregate({
      groupBy: ['status'],
      _count: true,
      orderBy: { status: 'asc' },
    })
    .orThrow();
}
