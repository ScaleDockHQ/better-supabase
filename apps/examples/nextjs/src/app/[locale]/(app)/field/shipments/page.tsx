import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import {
  activeView,
  RecordViewSwitch,
} from "@/components/record-list/record-view-switch";
import {
  FieldListSkeleton,
  ShipmentKpis,
  ShipmentOverview,
} from "@/features/field/components/field-overviews";
import {
  ShipmentTracking,
  ShipmentTrackingSkeleton,
} from "@/features/field/components/shipment-tracking";
import { parseBlockList } from "@/lib/block-overview-query";

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
        {searchParams.then((raw) => {
          const views = ["timeline", "table"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch
                base="/field/shipments"
                active={view}
                views={views}
              />
              {view === "table" ? (
                <>
                  <Suspense fallback={<KpiBandSkeleton />}>
                    <ShipmentKpis />
                  </Suspense>
                  <Suspense fallback={<FieldListSkeleton />}>
                    <ShipmentOverview query={parseBlockList(raw)} />
                  </Suspense>
                </>
              ) : (
                <ShipmentTracking query={raw} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
