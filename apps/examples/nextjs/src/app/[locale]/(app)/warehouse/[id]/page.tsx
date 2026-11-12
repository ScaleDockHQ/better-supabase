import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  PickListDetail,
  WarehouseDetailSkeleton,
} from "@/features/warehouse/components/warehouse-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the record streams in behind it.
export const instant = true;

export default function WarehousePickListPage({
  params,
  searchParams,
}: PageProps<"/[locale]/warehouse/[id]">) {
  const t = useExtracted("warehouse");

  return (
    <>
      <Link
        href="/warehouse"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All pick lists")}
      </Link>
      <Suspense fallback={<WarehouseDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <PickListDetail id={id} tab={activeTab(raw, ["lines", "details"])} />
        ))}
      </Suspense>
    </>
  );
}
