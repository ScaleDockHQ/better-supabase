import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AvailabilityEditor,
  AvailabilityEditorSkeleton,
} from "@/features/bookings/components/availability-editor";

export const instant = true;

export default function AvailabilityPage() {
  const t = useExtracted("bookings");

  return (
    <>
      <PageHeader
        title={t("Availability")}
        description={t(
          "When visitors of your booking link can book a time with you.",
        )}
      />
      <Suspense fallback={<AvailabilityEditorSkeleton />}>
        <AvailabilityEditor />
      </Suspense>
    </>
  );
}
