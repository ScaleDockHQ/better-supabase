import { riskList } from "../../../../features/risks/risk-list";
import { readRiskPage } from "../../../../features/risks/risks-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/risks/register?q=&sort=&status=&category=&band=&after=`: one keyset
 * page of risks with the band each one falls in, for the register's list kit.
 * The overview calls it for every URL state but the default page the server
 * renders. `/api/risks/list` is the generated route (ADR 0859) with the raw
 * page and the facet counts.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = riskList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  return Response.json(await readRiskPage(db, query.value));
});
