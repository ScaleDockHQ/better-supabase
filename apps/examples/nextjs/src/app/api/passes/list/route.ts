import { passList } from "../../../../features/passes/passes-list";
import { loadPassPage } from "../../../../features/passes/passes-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/passes/list?status=&after=`: one page of passes. The overview calls
 * it for every URL state but the default the server renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = passList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadPassPage(db, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
