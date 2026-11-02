import { bsb } from "../../../../../lib/supabase/server";

/**
 * `GET /api/customers/:id/reads`: who read the customer and when, from the read
 * log `subjects.customer.auditReads` keeps.
 */
export const GET = bsb.route<{ id: string }>((_request, { db, params }) =>
  db.subjects.reads.list({ subject: { type: "customer", id: params.id } }),
);
