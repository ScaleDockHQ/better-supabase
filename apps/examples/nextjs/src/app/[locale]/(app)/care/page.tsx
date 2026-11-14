import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ClientListSkeleton,
  ClientList,
} from "@/features/care/components/care-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CarePage() {
  const t = useExtracted("care");

  return (
    <>
      <PageHeader
        title={t("Clients")}
        description={t(
          "The clients in your care. Open one for their notes, care plan, observations, medication, consents and access log.",
        )}
      />
      <Suspense fallback={<ClientListSkeleton />}>
        <PermissionGate permission="customers.read">
          <ClientList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
