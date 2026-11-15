import { loadQualificationTypePage } from "@/features/qualifications/qualifications-queries";
import { qualificationTypeList } from "@/features/qualifications/qualifications-types-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/qualifications/list?q=&expiry=&state=&sort=&after=`: one page of
 * qualification types, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = qualificationTypeList.parse(request.nextUrl.searchParams);

    return Response.json(
      await loadQualificationTypePage(db, tenant, query.value),
    );
  },
  { requireTenant: true, permission: "qualifications.read" },
);
