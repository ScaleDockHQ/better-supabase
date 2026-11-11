import { loadAdminList } from "../../../../features/admin-lists/admin-list-load";
import { domainList } from "../../../../features/domains/domains-list";
import { domainSource } from "../../../../features/domains/domains-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/**
 * `GET /api/domains/list?q=&state=&kind=&sort=&after=`: one page of hostnames
 * with the count per facet value. The overview calls it for every URL state but
 * the default page the server renders.
 */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = domainList.parse(request.nextUrl.searchParams);

    if (!query.ok) {
      return Response.json({ issues: ["invalid list state"] }, { status: 400 });
    }

    return Response.json(
      await loadAdminList({
        session,
        tenant,
        list: domainList,
        source: domainSource,
        access: "admin",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "domains.read" },
);
