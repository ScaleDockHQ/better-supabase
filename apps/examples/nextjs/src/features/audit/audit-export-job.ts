import "server-only";
import { createAudit } from "better-supabase/blocks/audit";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { Temporal } from "temporal-polyfill";

import { serviceNotifications } from "@/features/workflows/workflow-steps";
import { serviceSupabase } from "@/lib/service-supabase";

import type { AuditExportInput } from "./audit-export";

import { EXPORT_BUCKET, exportPath, filtersOf } from "./audit-export";

/**
 * The export job: writes the matching entries as CSV to the data exports bucket
 * as the service role, then tells the requester through a notification whose
 * link is the download route. A failure throws, so the queue retries it.
 */
export async function runAuditExport(input: AuditExportInput): Promise<void> {
  const supabase = serviceSupabase();

  const audit = createAudit({
    transport: rpcTransport(supabase, { schema: "api" }),
    schema: "api",
    temporal: Temporal,
  });

  const stored = await audit
    .exportToStorage({
      ...filtersOf(input.tenant, input),
      format: "csv",
      storage: supabase.storage,
      bucket: EXPORT_BUCKET,
      path: exportPath(input.tenant, input.job),
    })
    .orThrow();

  await serviceNotifications()
    .send({
      type: "audit.export.ready",
      input: {
        tenant: input.tenant,
        recipients: [input.userId],
        includeActor: true,
        actionPath: `/api/audit/export/${input.job}`,
        data: { title: "Your audit log export is ready", job: input.job },
      },
    })
    .orThrow();

  console.info(`audit export ${input.job}: ${stored.path}`);
}
