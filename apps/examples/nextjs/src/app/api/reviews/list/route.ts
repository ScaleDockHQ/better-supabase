import { tenantOf } from "better-supabase/next";

import { reviewList } from "../../../../features/reviews/reviews-list";
import { loadReviewPage } from "../../../../features/reviews/reviews-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/reviews/list?status=`: the reviews of the selected statuses, newest
 * first. The overview calls it for every URL state but the default the server
 * renders.
 */
export const GET = bsb.route(async (request, { db, auth }) => {
  const query = reviewList.parse(request.nextUrl.searchParams);
  const organizationId = tenantOf(auth);

  if (!query.ok || !organizationId) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadReviewPage(db, organizationId, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
