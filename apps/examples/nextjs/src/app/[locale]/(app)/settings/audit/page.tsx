import { Suspense } from "react";

import {
  AuditLog,
  AuditLogSkeleton,
} from "@/features/audit/components/audit-log";

export default function AuditSettingsPage() {
  return (
    <Suspense fallback={<AuditLogSkeleton />}>
      <AuditLog />
    </Suspense>
  );
}
