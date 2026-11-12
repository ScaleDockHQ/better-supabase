import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  CountPlanDetail,
  WarehouseDetailSkeleton,
} from "@/features/warehouse/components/warehouse-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the record streams in behind it.
export const instant = true;

export default function WarehouseCountPage({
  params,
}: PageProps<"/[locale]/warehouse/counts/[id]">) {
  const t = useExtracted("warehouse");

  return (
    <>
      <Link
        href="/warehouse?tab=counts"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All count plans")}
      </Link>
      <Suspense fallback={<WarehouseDetailSkeleton />}>
        {params.then(({ id }) => (
          <CountPlanDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
