import {
  holdsPlatformPermission,
  getAdminList,
} from "../../../../features/admin-lists/admin-list-load";
import { flagList } from "../../../../features/flags/flags-list";
import { flagSource } from "../../../../features/flags/flags-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/** `GET /api/flags/list?q=&sort=&after=`: one page of flags. */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    if (!(await holdsPlatformPermission(session, "flags.manage"))) {
      return Response.json({ issues: ["forbidden"] }, { status: 403 });
    }

    const query = flagList.parse(request.nextUrl.searchParams);

    return Response.json(
      await getAdminList({
        session,
        tenant,
        list: flagList,
        source: flagSource,
        access: "admin",
        query: query.value,
      }),
    );
  },
  { requireTenant: true },
);
