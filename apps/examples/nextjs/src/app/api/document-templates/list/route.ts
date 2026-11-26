import { templateList } from "@/features/document-templates/document-templates-list";
import { getTemplatePage } from "@/features/document-templates/document-templates-queries";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/document-templates/list?q=&type=&active=&sort=&after=`: one page of
 * templates, searched, filtered and sorted by the document templates block's
 * page methods.
 */
export const GET = bsb.route(
  async (request, { db }) => {
    const query = templateList.parse(request.nextUrl.searchParams);

    return Response.json(await getTemplatePage(db, query.value));
  },
  { requireTenant: true, permission: "document_templates.read" },
);
