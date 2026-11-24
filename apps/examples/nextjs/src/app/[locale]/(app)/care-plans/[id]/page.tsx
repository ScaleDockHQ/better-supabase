import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  CarePlanDetail,
  CarePlanDetailSkeleton,
} from "@/features/care-plans/components/care-plan-detail";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the plan streams in.
export const instant = true;

export default function CarePlanPage({
  params,
  searchParams,
}: PageProps<"/[locale]/care-plans/[id]">) {
  const t = useExtracted("care-plans");

  return (
    <>
      <Link
        href="/care-plans"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All care plans")}
      </Link>
      <Suspense fallback={<CarePlanDetailSkeleton />}>
        <PermissionGate permission="care_plans.read">
          {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
            <CarePlanDetail
              id={id}
              tab={activeTab(raw, [
                "overview",
                "evaluations",
                "activity",
                "related",
              ])}
            />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
