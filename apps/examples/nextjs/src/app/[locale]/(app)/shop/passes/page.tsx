import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  PassList,
  PassListSkeleton,
} from "@/features/passes/components/pass-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of the overview stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

export const instant = true;

export default function PassesPage() {
  const t = useExtracted("passes");

  return (
    <>
      <PageHeader
        title={t("Passes")}
        description={t(
          "Entry passes and class credits, with their holders, uses and scans.",
        )}
      />
      <Suspense fallback={<PassListSkeleton />}>
        <PermissionGate permission="passes.read">
          <PassList />
        </PermissionGate>
      </Suspense>
    </>
  );
}
