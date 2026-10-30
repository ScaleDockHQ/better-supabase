import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  MedicationChart,
  MedicationChartSkeleton,
} from "@/features/medications/components/medication-chart";

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
