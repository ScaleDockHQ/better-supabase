import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ShipmentTracking,
  ShipmentTrackingSkeleton,
} from "@/features/field/components/shipment-tracking";

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
        <ShipmentTracking searchParams={searchParams} />
      </Suspense>
    </>
  );
}
