import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { getAppraisals } from "@/features/appraisals/appraisals-queries";
import {
  AppraisalList,
  AppraisalListSkeleton,
} from "@/features/appraisals/components/appraisal-list";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function Appraisals() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <AppraisalList
      state={await getAppraisals()}
      canManage={can(permissions, "appraisals.manage")}
    />
  );
}

export default function AppraisalsPage() {
  const t = useExtracted("appraisals");

  return (
    <>
      <PageHeader
        title={t("Appraisals")}
        description={t(
          "Review cycles with self, peer and manager reviews, calibration and sign-off.",
        )}
      />
      <Suspense fallback={<AppraisalListSkeleton />}>
        <PermissionGate permission="appraisals.review">
          <Appraisals />
        </PermissionGate>
      </Suspense>
    </>
  );
}
