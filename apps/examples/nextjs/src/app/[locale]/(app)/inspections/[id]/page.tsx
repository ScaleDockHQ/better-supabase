import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  InspectionDetail,
  InspectionDetailSkeleton,
} from "@/features/inspections/components/inspection-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the inspection streams in behind it.
export const instant = true;

export default function InspectionPage({
  params,
  searchParams,
}: PageProps<"/[locale]/inspections/[id]">) {
  const t = useExtracted("inspections");

  return (
    <>
      <Link
        href="/inspections/register"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All inspections")}
      </Link>
      <Suspense fallback={<InspectionDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <InspectionDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
