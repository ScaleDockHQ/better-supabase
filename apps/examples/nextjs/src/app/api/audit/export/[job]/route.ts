import { dbError, err } from "better-supabase";

import {
  EXPORT_BUCKET,
  EXPORT_LINK_SECONDS,
  exportPath,
} from "@/features/audit/audit-export";
import { serviceSupabase } from "@/lib/service-supabase";

import { bsb } from "../../../../../lib/supabase/server";

const JOB_ID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

/**
 * `GET /api/audit/export/<job>`: redirects to a short-lived signed link for a
 * finished export. The object path starts with the caller's organization, so
 * one organization can never sign another's file.
 */
export const GET = bsb.route<{ job: string }, true>(
  async (_request, { params, tenant }) => {
    if (!JOB_ID.test(params.job)) {
      return err(dbError("invalid_input", "Unknown export"));
    }

    const signed = await serviceSupabase()
      .storage.from(EXPORT_BUCKET)
      .createSignedUrl(exportPath(tenant, params.job), EXPORT_LINK_SECONDS, {
        download: `audit-${tenant}.csv`,
      });

    if (!signed.data) {
      return err(
        dbError("not_found", "The export is not ready or has expired"),
      );
    }

    return Response.redirect(signed.data.signedUrl, 302);
  },
  { requireTenant: true, permission: "audit.read" },
);
