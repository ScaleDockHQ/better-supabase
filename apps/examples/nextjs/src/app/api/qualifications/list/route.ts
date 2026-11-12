import { readQualificationTypeRows } from "@/features/qualifications/qualifications-queries";
import {
  qualificationTypeList,
  qualificationTypeSpec,
} from "@/features/qualifications/qualifications-types-list";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/qualifications/list?q=&expiry=&state=&sort=&after=`: one page of
 * qualification types, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const rows = await readQualificationTypeRows(db, tenant);
    const query = qualificationTypeList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(
        qualificationTypeList,
        qualificationTypeSpec,
        rows,
        query.value,
      ),
    );
  },
  { requireTenant: true, permission: "qualifications.read" },
);
