import { leaveList, leaveSpec } from "@/features/leave/leave-list";
import { readLeaveRows } from "@/features/leave/leave-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/leave/list?q=&status=&type=&sort=&after=`: one page of leave
 * requests, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db, tenant }) => {
    const { rows } = await readLeaveRows(db, tenant);
    const query = leaveList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(leaveList, leaveSpec, rows, query.value),
    );
  },
  { requireTenant: true, permission: "leave.request" },
);
