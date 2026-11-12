import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  MaintenanceDetailSkeleton,
  PlanDetail,
} from "@/features/maintenance/components/maintenance-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the plan streams in behind it.
export const instant = true;

export default function MaintenancePlanPage({
  params,
  searchParams,
}: PageProps<"/[locale]/maintenance/[id]">) {
  const t = useExtracted("maintenance");

  return (
    <>
      <Link
        href="/maintenance"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All plans")}
      </Link>
      <Suspense fallback={<MaintenanceDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <PlanDetail
            id={id}
            tab={activeTab(raw, ["overview", "parts", "work-order"])}
          />
        ))}
      </Suspense>
    </>
  );
}
