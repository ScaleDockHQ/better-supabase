import { getAdminList } from "../../../../features/admin-lists/admin-list-load";
import { oauthAppList } from "../../../../features/oauth-apps/oauth-apps-list";
import { oauthAppSource } from "../../../../features/oauth-apps/oauth-apps-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/** `GET /api/oauth-apps/list?q=&sort=&after=`: one page of oauth apps. */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = oauthAppList.parse(request.nextUrl.searchParams);

    return Response.json(
      await getAdminList({
        session,
        tenant,
        list: oauthAppList,
        source: oauthAppSource,
        access: "admin",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "settings.manage" },
);
