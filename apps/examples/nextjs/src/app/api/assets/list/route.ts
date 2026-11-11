import { assetList } from "../../../../features/assets/assets-list";
import { loadAssetPage } from "../../../../features/assets/assets-queries";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/assets/list?q=&status=&after=`: one page of the register, filtered
 * in the database by the assets block. The overview calls it for every URL
 * state but the default page the server renders.
 */
export const GET = bsb.route(async (request, { db }) => {
  const query = assetList.parse(request.nextUrl.searchParams);

  if (!query.ok) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const page = await loadAssetPage(db, query.value);

  return page.ok
    ? Response.json(page.data)
    : Response.json({ error: page.error.code }, { status: 500 });
});
