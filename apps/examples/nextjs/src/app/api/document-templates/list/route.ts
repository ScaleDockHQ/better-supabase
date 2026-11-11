import {
  templateList,
  templateSpec,
} from "@/features/document-templates/document-templates-list";
import { readTemplateRows } from "@/features/document-templates/document-templates-queries";
import { pageBlockRows } from "@/lib/block-list";
import { bsb } from "@/lib/supabase/server";

/**
 * `GET /api/document-templates/list?q=&type=&active=&sort=&after=`: one page of
 * templates, searched, filtered and sorted on the server.
 */
export const GET = bsb.route(
  async (request, { db }) => {
    const rows = await readTemplateRows(db);
    const query = templateList.parse(request.nextUrl.searchParams);

    return Response.json(
      pageBlockRows(templateList, templateSpec, rows, query.value),
    );
  },
  { requireTenant: true, permission: "document_templates.read" },
);
