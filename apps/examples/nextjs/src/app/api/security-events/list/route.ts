import { getAdminList } from "../../../../features/admin-lists/admin-list-load";
import { securityStreamList } from "../../../../features/security-events/security-events-list";
import { securityStreamSource } from "../../../../features/security-events/security-events-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/** `GET /api/security-events/list?q=&sort=&after=`: one page of security events. */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = securityStreamList.parse(request.nextUrl.searchParams);

    return Response.json(
      await getAdminList({
        session,
        tenant,
        list: securityStreamList,
        source: securityStreamSource,
        access: "admin",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "audit.read" },
);
