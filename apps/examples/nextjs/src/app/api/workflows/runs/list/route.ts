import { runList } from "@/features/workflows/workflow-lists";
import {
  definitionNames,
  queryRuns,
} from "@/features/workflows/workflows-list-data";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/workflows/runs/list?q=&status=&mode=&definition=&since=&after=`:
 * one page of the organization's runs, newest first.
 */
export const GET = bsb.route(
  async (request, { tenant, supabase }) => {
    const query = runList.parse(request.nextUrl.searchParams);

    if (!query.ok) {
      return Response.json({ issues: [] }, { status: 400 });
    }

    const names = await definitionNames(supabase, tenant);

    return Response.json(await queryRuns(supabase, tenant, query.value, names));
  },
  { requireTenant: true, permission: "workflows.read" },
);
