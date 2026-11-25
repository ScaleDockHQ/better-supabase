import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { FinanceOverviewPage } from "@/components/finance-pages/finance-pages";
import {
  CollectionsSection,
  CollectionsSectionSkeleton,
} from "@/features/dunning/components/collections-section";
import { PermissionGate } from "@/features/user/components/permission-gate";

// A prefetch of this list stays static; the rows render on navigation.
export const ensureStatic = "prefetch";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/loading-sequences.spec.ts checks it in a build.
export const instant = true;

export default function InvoicesPage() {
  const t = useExtracted("finance");

  return (
    <>
      <FinanceOverviewPage entity="invoices" />
      <section className="flex flex-col gap-4">
        <div className="space-y-1">
          <h2 className="text-lg font-semibold tracking-tight">
            {t("Collections")}
          </h2>
          <p className="text-sm text-muted-foreground">
            {t("How overdue sales invoices are reminded.")}
          </p>
        </div>
        <Suspense fallback={<CollectionsSectionSkeleton />}>
          <PermissionGate permission="invoices.read">
            <CollectionsSection />
          </PermissionGate>
        </Suspense>
      </section>
    </>
  );
}
