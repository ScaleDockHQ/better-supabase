import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  WorkOrderDetail,
  WorkOrderDetailSkeleton,
} from "@/features/field/components/work-order-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the work order desk streams in.
export const instant = true;

export default function WorkOrderPage({
  params,
  searchParams,
}: PageProps<"/[locale]/field/dispatch/[id]">) {
  const t = useExtracted("field");

  return (
    <>
      <Link
        href="/field/dispatch?view=table"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All work orders")}
      </Link>
      <Suspense fallback={<WorkOrderDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <WorkOrderDetail
            id={id}
            tab={activeTab(raw, ["overview", "activity", "related"])}
          />
        ))}
      </Suspense>
    </>
  );
}
