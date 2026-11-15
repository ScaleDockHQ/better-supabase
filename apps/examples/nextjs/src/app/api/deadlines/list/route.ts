import { deadlineList } from "@/features/deadlines/deadlines-list";
import { loadDeadlinePage } from "@/features/deadlines/deadlines-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/deadlines/list?q=&state=&result=&group=&sort=&after=`: one page of
 * deadlines, searched, filtered and sorted by the deadlines block's page
 * methods.
 */
export const GET = bsb.route(
  async (request, { db }) => {
    const query = deadlineList.parse(request.nextUrl.searchParams);

    return Response.json(await loadDeadlinePage(db, query.value));
  },
  { requireTenant: true, permission: "deadlines.read" },
);
