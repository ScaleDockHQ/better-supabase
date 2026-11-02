import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  Prescriptions,
  PrescriptionsSkeleton,
} from "@/features/e-prescribing/components/prescriptions";
import { getPrescriptions } from "@/features/e-prescribing/prescriptions-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function PrescriptionList() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <Prescriptions
      state={await getPrescriptions()}
      canSign={can(permissions, "e_prescribing.sign")}
      canCancel={can(permissions, "e_prescribing.write")}
    />
  );
}

export default function PrescriptionsPage() {
  const t = useExtracted("prescriptions");

  return (
    <>
      <PageHeader
        title={t("Prescriptions")}
        description={t(
          "Drafts the prescriber signs, then a gateway sends them to the pharmacy.",
        )}
      />
      <Suspense fallback={<PrescriptionsSkeleton />}>
        <PermissionGate permission="e_prescribing.read">
          <PrescriptionList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
