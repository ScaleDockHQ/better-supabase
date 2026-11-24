import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  ShipmentDetail,
  ShipmentDetailSkeleton,
} from "@/features/field/components/shipment-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the shipment desk streams in.
export const instant = true;

export default function ShipmentPage({
  params,
  searchParams,
}: PageProps<"/[locale]/field/shipments/[id]">) {
  const t = useExtracted("field");

  return (
    <>
      <Link
        href="/field/shipments?view=table"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All shipments")}
      </Link>
      <Suspense fallback={<ShipmentDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <ShipmentDetail
            id={id}
            tab={activeTab(raw, ["overview", "related", "activity"])}
          />
        ))}
      </Suspense>
    </>
  );
}
