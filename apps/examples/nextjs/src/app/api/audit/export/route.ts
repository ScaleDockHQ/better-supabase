import type { AuditListOptions } from "better-supabase/blocks/audit";

import { dbError, err } from "better-supabase";
import { hasEntitlement } from "better-supabase/blocks/entitlements";

import { bsb } from "../../../../lib/supabase/server";

/** The most rows one request streams; a larger range needs a narrower filter. */
const MAX_ROWS = 100_000;

const DEFAULT_WINDOW_HOURS = 30 * 24;

type Filters = { -readonly [K in keyof AuditListOptions]: AuditListOptions[K] };

/**
 * `GET /api/audit/export?actor=&type=&from=&to=&q=`: the active organization's
 * audit log as CSV for the same filters and window as the page (the last 30
 * days without `from`), streamed page by page from the audit module.
 */
export const GET = bsb.route(
  async (request, { session, tenant: organizationId, db }) => {
    if (!hasEntitlement(session, organizationId, "audit")) {
      return err(dbError("forbidden", "The audit log is not in your plan"));
    }

    if (!hasEntitlement(session, organizationId, "exports")) {
      return err(dbError("forbidden", "CSV exports are not in your plan"));
    }

    const params = new URL(request.url).searchParams;
    const from = params.get("from");
    const to = params.get("to");
    const actor = params.get("actor");
    const type = params.get("type");
    const search = params.get("q");

    const filters: Filters = {
      organizationId,
      since: from
        ? Temporal.Instant.from(from)
        : Temporal.Now.instant().subtract({ hours: DEFAULT_WINDOW_HOURS }),
    };

    if (to) {
      filters.until = Temporal.Instant.from(to);
    }

    if (actor) {
      filters.actorId = actor;
    }

    if (type) {
      filters.eventType = type;
    }

    if (search) {
      filters.search = search;
    }

    const probe = await db.audit.list({
      ...filters,
      limit: 1,
      fields: "summary",
      count: true,
      countCap: MAX_ROWS + 1,
    });

    if (!probe.ok) {
      return probe;
    }

    if ((probe.data.total ?? 0) > MAX_ROWS) {
      return err(
        dbError(
          "invalid_input",
          `More than ${String(MAX_ROWS)} entries match; narrow the dates or filters`,
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
