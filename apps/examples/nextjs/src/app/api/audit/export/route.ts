import { dbError, err } from "better-supabase";
import { hasEntitlement } from "better-supabase/blocks/entitlements";

import { getPermissions } from "@/features/user/permission-snapshot";

import { can } from "../../../../features/user/user-permissions";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/audit/export`: the active organization's audit log as CSV, streamed
 * page by page from the audit module.
 */
export const GET = bsb.route(
  (_request, { session, tenant: organizationId, db }) => {
    if (!hasEntitlement(session, organizationId, "audit")) {
      return err(dbError("forbidden", "The audit log is not in your plan"));
    }

    if (!hasEntitlement(session, organizationId, "exports")) {
      return err(dbError("forbidden", "CSV exports are not in your plan"));
    }

    const stream = db.audit.export({ organizationId, format: "csv" });

    return new Response(stream, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="audit-${organizationId}.csv"`,
        "cache-control": "no-store",
      },
    });
  },
  {
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "audit.read"),
  },
);
