import { loadAdminList } from "../../../../features/admin-lists/admin-list-load";
import { jobList } from "../../../../features/jobs/jobs-list";
import { JOBS_PERMISSION } from "../../../../features/jobs/jobs-server";
import { jobSource, queueNames } from "../../../../features/jobs/jobs-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/**
 * `GET /api/jobs/list?q=&status=&queue=&sort=&after=`: one page of the
 * organization's job runs with the count per status and queue.
 */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = jobList.parse(request.nextUrl.searchParams);

    if (!query.ok) {
      return Response.json({ issues: ["invalid list state"] }, { status: 400 });
    }

    return Response.json(
      await loadAdminList({
        session,
        tenant,
        list: jobList,
        source: jobSource(await queueNames()),
        access: "admin",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: JOBS_PERMISSION },
);
