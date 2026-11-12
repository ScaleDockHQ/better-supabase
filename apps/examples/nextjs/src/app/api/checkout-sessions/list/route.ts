import { sessionList } from "../../../../features/checkout-sessions/checkout-sessions-list";
import { loadSessionPage } from "../../../../features/checkout-sessions/checkout-sessions-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/checkout-sessions/list?status=&protocol=`: the sessions the filters
 * keep. The overview calls it for every URL state but the default the server
 * renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = sessionList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadSessionPage(db, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
