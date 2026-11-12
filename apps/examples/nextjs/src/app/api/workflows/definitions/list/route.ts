import { definitionList } from "@/features/workflows/workflow-lists";
import { queryDefinitions } from "@/features/workflows/workflows-list-data";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/workflows/definitions/list?q=&state=&sort=&after=`: one page of the
 * organization's workflow definitions. The overview calls it for every URL
 * state but the default page the server renders.
 */
export const GET = bsb.route(
  async (request, { tenant, supabase }) => {
    const query = definitionList.parse(request.nextUrl.searchParams);

    if (!query.ok) {
      return Response.json({ issues: [] }, { status: 400 });
    }

    return Response.json(await queryDefinitions(supabase, tenant, query.value));
  },
  { requireTenant: true, permission: "workflow_editor.read" },
);
