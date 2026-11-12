import { leaseList } from "../../../../features/leases/leases-list";
import { loadLeasePage } from "../../../../features/leases/leases-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/leases/list?status=`: the leases of the selected statuses. The
 * overview calls it for every URL state but the default the server renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = leaseList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadLeasePage(db, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
