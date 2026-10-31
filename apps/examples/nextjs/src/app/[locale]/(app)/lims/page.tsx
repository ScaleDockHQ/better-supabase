import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { Samples, SamplesSkeleton } from "@/features/lims/components/samples";
import { getSamples } from "@/features/lims/lims-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function SampleList() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <Samples
      state={await getSamples()}
      canWrite={can(permissions, "lims.write")}
    />
  );
}

export default function LimsPage() {
  const t = useExtracted("lims");

  return (
    <>
      <PageHeader
        title={t("Laboratory")}
        description={t(
          "Samples, their results and whether they may be released.",
        )}
      />
      <Suspense fallback={<SamplesSkeleton />}>
        <PermissionGate permission="lims.read">
          <SampleList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
