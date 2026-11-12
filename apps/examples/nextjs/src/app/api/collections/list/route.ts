import { tenantOf } from "better-supabase/next";

import { collectionList } from "../../../../features/collections/collections-list";
import { loadCollectionPage } from "../../../../features/collections/collections-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/collections/list?scope=&state=`: the collections the filters keep.
 * The overview calls it for every URL state but the default the server
 * renders.
 */
export const GET = bsb.route(async (request, { db, auth }) => {
  const query = collectionList.parse(request.nextUrl.searchParams);
  const organizationId = tenantOf(auth);

  if (!query.ok || !organizationId) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadCollectionPage(db, organizationId, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
