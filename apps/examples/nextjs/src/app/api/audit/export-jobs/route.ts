import { dbError, err, ok } from "better-supabase";
import { hasEntitlement } from "better-supabase/blocks/entitlements";

import { env } from "@/env";
import { paramsOf } from "@/features/audit/audit-export";
import { AUDIT_EXPORT_QUEUE, pushJobs } from "@/features/jobs/jobs-server";

import { bsbCore } from "../../../../lib/supabase/server-core";

/**
 * `POST /api/audit/export-jobs?...` (same filters as the export): queues the
 * export on Vercel Queues for any range. The job writes the CSV to the data
 * exports bucket and sends the caller a notification that links to `GET
 * /api/audit/export/<job>`.
 */
export const POST = bsbCore.route(
  async (request, { session, tenant: organizationId, auth }) => {
    if (!hasEntitlement(session, organizationId, "audit")) {
      return err(dbError("forbidden", "The audit log is not in your plan"));
    }

    if (!hasEntitlement(session, organizationId, "exports")) {
      return err(dbError("forbidden", "CSV exports are not in your plan"));
    }

    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to export the audit log"));
    }

    if (env.JOBS_BACKEND !== "vercel") {
      return err(
        dbError(
          "network",
          "Set JOBS_BACKEND=vercel to run export jobs on Vercel Queues",
        ),
      );
    }

    const job = crypto.randomUUID();

    const queued = await pushJobs.enqueue({
      queue: AUDIT_EXPORT_QUEUE,
      payload: {
        job,
        tenant: organizationId,
        userId: auth.user.id,
        ...paramsOf(new URL(request.url).searchParams),
      },
      context: {
        actor: { kind: "user", id: auth.user.id },
        tenant: organizationId,
      },
    });

    return queued.ok ? ok({ job }) : queued;
  },
  { requireTenant: true, permission: "audit.read" },
);
