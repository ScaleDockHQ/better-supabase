import { financeOverview } from "../../../../../lib/read-sets";
import { bsb } from "../../../../../lib/supabase/server";

/**
 * `GET /api/banking/:id/overview`: the bank account's reconciliation board and
 * the stock watch list in one round trip, from the `finance_overview` read
 * set.
 */
export const GET = bsb.route<{ id: string }, true>(
  (_request, { db, params, tenant }) =>
    db.$many(financeOverview, { accountId: params.id, organizationId: tenant }),
  { requireTenant: true },
);
