import { Suspense } from "react";

import { loadAuditFilters } from "@/features/audit/audit-search-params";
import {
  AuditLog,
  AuditLogSkeleton,
} from "@/features/audit/components/audit-log";

export default function AuditSettingsPage({
  searchParams,
}: PageProps<"/[locale]/settings/audit">) {
  return (
    <Suspense fallback={<AuditLogSkeleton />}>
      <AuditLog filters={searchParams.then(loadAuditFilters)} />
    </Suspense>
  );
}
