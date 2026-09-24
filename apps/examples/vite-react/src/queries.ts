import type { Queries } from 'better-supabase/query';

import type { Models } from './lib/supabase';

type AppQueries = Queries<Models, unknown>;

export const customerList = (queries: AppQueries, search = '') =>
  queries.customers.findMany({
    select: ['id', 'name', 'status'],
    ...(search ? { where: { name: { ilike: `%${search}%` } } } : {}),
    orderBy: { name: 'asc' },
    limit: 50,
  });

export const createCustomer = (queries: AppQueries) =>
  queries.customers.create({ select: ['id', 'name', 'status'] });
