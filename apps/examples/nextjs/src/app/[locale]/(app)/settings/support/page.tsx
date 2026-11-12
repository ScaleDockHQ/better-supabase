import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { RequestSupportDialog } from "@/features/support/components/request-support-dialog";
import {
  SupportSessions,
  SupportSessionsSkeleton,
} from "@/features/support/components/support-sessions";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function SupportSettingsPage() {
  const t = useExtracted("support");

  return (
    <>
      <PageHeader
        title={t("Support sessions")}
        description={t(
          "Platform staff view the app as a user for a short time: read-only, approved by a second admin and recorded in the audit log.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="impersonation.start">
              <RequestSupportDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SupportSessionsSkeleton />}>
        <PermissionGate permission="impersonation.read">
          <SupportSessions />
        </PermissionGate>
      </Suspense>
    </>
  );
}
