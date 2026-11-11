import {
  deadlineList,
  deadlineSpec,
} from "@/features/deadlines/deadlines-list";
import { readDeadlineRows } from "@/features/deadlines/deadlines-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/deadlines/list?q=&state=&result=&kind=&sort=&after=`: one page of
 * deadlines, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db }) => {
    const rows = await readDeadlineRows(db);
    const query = deadlineList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(deadlineList, deadlineSpec, rows, query.value),
    );
  },
  { requireTenant: true, permission: "deadlines.read" },
);
