import { type BetterEnv, createHono } from 'better-supabase/hono';
import { defineListQuery } from 'better-supabase/list';
import { Hono } from 'hono';

import { type Functions, type Models, sb } from './lib/supabase';

const bs = createHono(sb);

const customers = defineListQuery(sb, 'customers', {
  search: ['name'],
  facets: { status: 'status' },
  sorts: { name: { name: 'asc' }, newest: { createdAt: 'desc' } },
  defaultSort: 'name',
  pageSize: 20,
});

const app = new Hono<BetterEnv<Models, Functions, unknown>>()
  .onError(bs.onError)
  .use('/api/*', bs.middleware())
  .get('/api/me', (c) => c.json({ kind: c.var.auth.kind }))
  .route(
    '/api/customers',
    bs.resource('customers', {
      list: customers,
      select: ['id', 'name', 'status', 'organizationId', 'createdAt'],
    }),
  )
  .get('/api/customers/:id/notes', async (c) => {
    const notes = await c.var.db.notes
      .findMany({
        select: ['id', 'body', 'kind', 'createdAt'],
        where: { customerId: c.req.param('id') },
        orderBy: { createdAt: 'desc' },
      })
      .orThrow();
    return c.json({ items: notes });
  });

export default app;
