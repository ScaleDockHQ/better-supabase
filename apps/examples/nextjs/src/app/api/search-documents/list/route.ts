import { loadAdminList } from "../../../../features/admin-lists/admin-list-load";
import { searchDocumentList } from "../../../../features/search-settings/search-settings-list";
import { searchDocumentSource } from "../../../../features/search-settings/search-settings-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/** `GET /api/search-documents/list?q=&sort=&after=`: one page of search index. */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = searchDocumentList.parse(request.nextUrl.searchParams);

    if (!query.ok) {
      return Response.json({ issues: ["invalid list state"] }, { status: 400 });
    }

    return Response.json(
      await loadAdminList({
        session,
        tenant,
        list: searchDocumentList,
        source: searchDocumentSource,
        access: "user",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "settings.read" },
);
