import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  FrontDesk,
  FrontDeskSkeleton,
} from "@/features/calendar/components/front-desk";

// The header and the skeleton paint at once; the schedule streams in.
export const instant = true;

export default function FrontDeskPage() {
  const t = useExtracted("calendar");

  return (
    <>
      <PageHeader
        title={t("Front desk")}
        description={t("What is on today and in the coming days.")}
      />
      <Suspense fallback={<FrontDeskSkeleton />}>
        <FrontDesk />
      </Suspense>
    </>
  );
}
