import { Suspense } from "react";

import { loadAuditFilters } from "@/features/audit/audit-search-params";
import {
  AuditLog,
  AuditLogSkeleton,
} from "@/features/audit/components/audit-log";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function AuditSettingsPage({
  searchParams,
}: PageProps<"/[locale]/settings/audit">) {
  return (
    <Suspense fallback={<AuditLogSkeleton />}>
      <AuditLog filters={searchParams.then(loadAuditFilters)} />
    </Suspense>
  );
}
