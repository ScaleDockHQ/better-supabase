import { next } from '../../../../lib/supabase.server';

export const GET = next.route<{ id: string }>((_request, { db, params }) =>
  db.customers.findById(params.id, {
    select: ['id', 'name', 'status', 'organizationId'],
  }),
);
