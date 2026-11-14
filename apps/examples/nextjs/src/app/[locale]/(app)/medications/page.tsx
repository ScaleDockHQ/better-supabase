import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MedicationChart,
  MedicationChartSkeleton,
} from "@/features/medications/components/medication-chart";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function MedicationsPage() {
  const t = useExtracted("medications");

  return (
    <>
      <PageHeader
        title={t("Medications")}
        description={t(
          "Today's medication chart: what each order gives and which doses are given, refused or missed.",
        )}
      />
      <Suspense fallback={<MedicationChartSkeleton />}>
        <MedicationChart />
      </Suspense>
    </>
  );
}
