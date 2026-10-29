import type {
  DataExport,
  DataExportStatus,
} from "better-supabase/blocks/data-lifecycle";

import { tenantOf } from "better-supabase/next";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

export interface ExportRow {
  readonly id: string;
  readonly status: DataExportStatus;
  readonly files: number;
  readonly error: string | null;
  readonly requestedAt: string;
  readonly expiresAt: string | null;
}

export interface PrivacyData {
  readonly mine: readonly ExportRow[];
  /** `null` when the caller may not export the organization. */
  readonly organization: readonly ExportRow[] | null;
  readonly canDelete: boolean;
  /** When the pending purge runs, or `null` when no deletion is pending. */
  readonly purgeAfter: string | null;
}

function toRow(item: DataExport): ExportRow {
  return {
    error: item.error ?? null,
    expiresAt: item.expiresAt?.toString() ?? null,
    files: item.files.length,
    id: item.id,
    requestedAt: item.requestedAt.toString(),
    status: item.status,
  };
}

/**
 * The caller's exports, the organization's exports when the caller holds
 * `data_lifecycle.export`, and the pending deletion. A failed read throws, so
 * it is never cached and Retry reads again.
 */
export async function loadPrivacy(): Promise<PrivacyData> {
  "use cache: private";

  const [{ session, db }, permissions] = await Promise.all([
    bsb.cached(),
    getPermissions(),
  ]);

  const tenant = tenantOf(session);
  const { dataLifecycle } = db;

  const canExport =
    tenant !== undefined && can(permissions, "data_lifecycle.export");

  const [mine, organization, deletion] = await Promise.all([
    dataLifecycle.exports().orThrow(),
    canExport ? dataLifecycle.exports(tenant).orThrow() : null,
    tenant ? dataLifecycle.organizationDeletion(tenant).orThrow() : undefined,
  ]);

  return {
    canDelete: tenant !== undefined && can(permissions, "organization.delete"),
    mine: mine.filter((item) => item.subject === "user").map(toRow),
    organization: organization?.map(toRow) ?? null,
    purgeAfter:
      deletion && deletion.purgedAt === undefined
        ? deletion.purgeAfter.toString()
        : null,
  };
}
