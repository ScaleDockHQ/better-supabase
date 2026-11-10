import { dbError, err, ok } from "better-supabase";
import { hasEntitlement } from "better-supabase/blocks/entitlements";

import {
  EXPORT_ROW_LIMIT,
  filtersOf,
  paramsOf,
} from "@/features/audit/audit-export";

import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/audit/export?actor=&type=&from=&to=&q=`: the active organization's
 * audit log as CSV for the same filters and window as the page (the last 30
 * days without `from`), streamed page by page from the audit module. Up to
 * 100,000 rows; a larger range needs the job at `/api/audit/export-jobs`. With
 * `probe=1` it answers `{ rows, limit }` instead, so the page can pick between
 * the two.
 */
export const GET = bsb.route(
  async (request, { session, tenant: organizationId, db }) => {
    if (!hasEntitlement(session, organizationId, "audit")) {
      return err(dbError("forbidden", "The audit log is not in your plan"));
    }

    if (!hasEntitlement(session, organizationId, "exports")) {
      return err(dbError("forbidden", "CSV exports are not in your plan"));
    }

    const search = new URL(request.url).searchParams;
    const filters = filtersOf(organizationId, paramsOf(search));

    const probe = await db.audit.list({
      ...filters,
      limit: 1,
      fields: "summary",
      count: true,
      countCap: EXPORT_ROW_LIMIT + 1,
    });

    if (!probe.ok) {
      return probe;
    }

    const rows = probe.data.total ?? 0;

    if (search.get("probe") === "1") {
      return ok({ rows, limit: EXPORT_ROW_LIMIT });
    }

    if (rows > EXPORT_ROW_LIMIT) {
      return err(
        dbError(
          "invalid_input",
          `More than ${String(EXPORT_ROW_LIMIT)} entries match; start the export job or narrow the dates`,
        ),
      );
    }

    const stream = db.audit.export({ ...filters, format: "csv" });

    return new Response(stream, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="audit-${organizationId}.csv"`,
        "cache-control": "no-store",
      },
    });
  },
  { requireTenant: true, permission: "audit.read" },
);
