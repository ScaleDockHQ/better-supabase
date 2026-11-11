import {
  FINANCE_ENTITIES,
  defineFinanceList,
  type FinanceEntityKey,
} from "../../../../../lib/finance-list";
import { runFinanceList } from "../../../../../features/finance-records/finance-records-queries";
import { bsbCore as bsb } from "../../../../../lib/supabase/server-core";

const isEntity = (value: string): value is FinanceEntityKey =>
  Object.hasOwn(FINANCE_ENTITIES, value);

/**
 * `GET /api/finance/<entity>/list?q=&sort=&after=&status=a,b`: one page of an
 * entity's rows from `api.finance_list`, as the overview asks for every URL
 * state but the default page the server renders.
 */
export const GET = bsb.route<{ entity: string }, true>(
  async (request, { db, params, tenant }) => {
    if (!isEntity(params.entity)) {
      return Response.json({ issues: ["unknown entity"] }, { status: 404 });
    }

    const parsed = defineFinanceList(params.entity).parse(
      request.nextUrl.searchParams,
    );

    if (!parsed.ok) {
      return Response.json({ issues: ["invalid query"] }, { status: 400 });
    }

    return Response.json(
      await runFinanceList(db, tenant, params.entity, parsed.value),
    );
  },
  { requireTenant: true },
);
