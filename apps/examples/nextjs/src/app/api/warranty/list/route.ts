import { claimList } from "../../../../features/warranty/warranty-list";
import { loadClaimPage } from "../../../../features/warranty/warranty-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/warranty/list?status=`: the claims of the selected statuses. The
 * overview calls it for every URL state but the default the server renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = claimList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadClaimPage(db, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
