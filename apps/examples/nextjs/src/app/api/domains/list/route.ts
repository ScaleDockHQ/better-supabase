import { loadDomainPage } from "@/features/domains/domains-queries";
import { domainList } from "@/features/domains/domains-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/domains/list?q=&verified=&kind=&sort=&after=`: one page of
 * hostnames, searched, filtered and sorted on the server, with the count per
 * facet value. The overview calls it for every URL state but the default page
 * the server renders.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = domainList.parse(request.nextUrl.searchParams);

    return Response.json(await loadDomainPage(db, tenant, query.value));
  },
  { requireTenant: true, permission: "domains.read" },
);
