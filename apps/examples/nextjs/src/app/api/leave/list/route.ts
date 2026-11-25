import { leaveList } from "@/features/leave/leave-list";
import { getLeavePage } from "@/features/leave/leave-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/leave/list?q=&status=&type=&sort=&after=`: one page of leave
 * requests, searched, filtered and sorted by the leave block's page methods.
 * The block's row policies decide whose requests the caller reads.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const query = leaveList.parse(request.nextUrl.searchParams);
    const { page } = await getLeavePage(db, tenant, query.value);

    return Response.json(page);
  },
  { requireTenant: true, permission: "leave.request" },
);
