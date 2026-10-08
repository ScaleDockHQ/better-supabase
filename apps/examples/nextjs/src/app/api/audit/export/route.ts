import { dbError, err } from "better-supabase";
import { hasEntitlement } from "better-supabase/blocks/entitlements";

import { can } from "../../../../features/user/user-permissions";
import { blocks } from "../../../../lib/blocks";
import { bs } from "../../../../lib/supabase/server";

/**
 * `GET /api/audit/export`: the active organization's audit log as CSV,
 * streamed page by page from the audit module.
 */
export const GET = bs.route(
  (_request, { session, tenant: organizationId, supabase }) => {
    if (!hasEntitlement(session, organizationId, "audit")) {
      return err(dbError("forbidden", "The audit log is not in your plan"));
    }
    const stream = blocks(supabase).audit.export({
      organizationId,
      format: "csv",
    });
    return new Response(stream, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="audit-${organizationId}.csv"`,
        "cache-control": "no-store",
      },
    });
  },
  {
    requireTenant: true,
    authorize: (session) => can(session, "audit.read"),
  },
);
