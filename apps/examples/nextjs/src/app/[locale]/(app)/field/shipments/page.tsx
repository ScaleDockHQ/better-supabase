import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ShipmentTracking,
  ShipmentTrackingSkeleton,
} from "@/features/field/components/shipment-tracking";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ShipmentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("field");

  return (
    <>
      <PageHeader
        title={t("Shipments")}
        description={t("Track packages from label to delivery.")}
      />
      <Suspense fallback={<ShipmentTrackingSkeleton />}>
        {searchParams.then((query) => (
          <ShipmentTracking query={query} />
        ))}
      </Suspense>
    </>
  );
}
