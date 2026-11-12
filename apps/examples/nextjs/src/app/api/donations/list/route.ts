import { giftList } from "../../../../features/donations/donations-list";
import { loadGiftPage } from "../../../../features/donations/donations-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/donations/list?status=`: the gifts of the selected statuses. The
 * overview calls it for every URL state but the default the server renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = giftList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadGiftPage(db, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
