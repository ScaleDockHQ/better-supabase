import 'server-only';
import { customerList } from '@/lib/lists';
import { next } from '@/lib/supabase.server';

/**
 * The first page of the caller's customers plus the count per status.
 * `next.cached()` queries with the user's token, so RLS decides the rows;
 * the private cache keeps them in this browser only, for as long as the
 * session view may be reused. The page doesn't read `searchParams`, so it
 * stays in the instant App Shell; filtered pages go through
 * `/api/customers/list`.
 */
export async function getCustomers() {
  'use cache: private';
  const { db } = await next.cached();
  return customerList
    .run(db, customerList.defaults, {
      select: ['id', 'name', 'status'],
      // Counted and maxed in the database, in the same request.
      include: {
        _count: { notes: true },
        _max: { notes: { createdAt: true } },
      },
    })
    .orThrow();
}
