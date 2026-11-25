import { getAdminList } from "../../../../features/admin-lists/admin-list-load";
import { numberingList } from "../../../../features/numbering/numbering-list";
import { numberingSource } from "../../../../features/numbering/numbering-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/** `GET /api/numbering/list?q=&sort=&after=`: one page of numbering. */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = numberingList.parse(request.nextUrl.searchParams);

    return Response.json(
      await getAdminList({
        session,
        tenant,
        list: numberingList,
        source: numberingSource,
        access: "admin",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "numbering.read" },
);
