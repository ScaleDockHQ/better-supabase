import { loadAdminList } from "../../../../features/admin-lists/admin-list-load";
import { creditList } from "../../../../features/credits/credits-list";
import { creditEntrySource } from "../../../../features/credits/credits-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/** `GET /api/credits/list?q=&kind=&sort=&after=`: one page of credit entries. */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = creditList.parse(request.nextUrl.searchParams);

    return Response.json(
      await loadAdminList({
        session,
        tenant,
        list: creditList,
        source: creditEntrySource,
        access: "user",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "billing.read" },
);
