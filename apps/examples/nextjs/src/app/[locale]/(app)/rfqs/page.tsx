import { useExtracted } from "next-intl";
import { connection } from "next/server";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { Rfqs, RfqsSkeleton } from "@/features/rfqs/components/rfqs";
import { getRfqs } from "@/features/rfqs/rfqs-queries";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

async function RfqList() {
  const [permissions] = await Promise.all([getPermissions(), connection()]);

  return (
    <Rfqs state={await getRfqs()} canWrite={can(permissions, "rfqs.write")} />
  );
}

export default function RfqsPage() {
  const t = useExtracted("rfqs");

  return (
    <>
      <PageHeader
        title={t("Requests for quotation")}
        description={t(
          "Requests sent to suppliers, their quotes and the award.",
        )}
      />
      <Suspense fallback={<RfqsSkeleton />}>
        <PermissionGate permission="rfqs.read">
          <RfqList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
