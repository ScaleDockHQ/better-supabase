import { riskList } from "../../../../features/risks/risk-list";
import { readRiskPage } from "../../../../features/risks/risks-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/risks/list?q=&status=&category=&band=&after=`: one keyset page of
 * risks, the highest residual score first. The overview calls it for every URL
 * state but the default page the server renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = riskList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  return Response.json(await readRiskPage(db, query.value));
});
