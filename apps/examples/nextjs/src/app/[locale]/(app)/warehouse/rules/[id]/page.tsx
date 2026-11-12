import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RuleDetail,
  WarehouseDetailSkeleton,
} from "@/features/warehouse/components/warehouse-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the record streams in behind it.
export const instant = true;

export default function WarehouseRulePage({
  params,
}: PageProps<"/[locale]/warehouse/rules/[id]">) {
  const t = useExtracted("warehouse");

  return (
    <>
      <Link
        href="/warehouse?tab=putaway"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All putaway rules")}
      </Link>
      <Suspense fallback={<WarehouseDetailSkeleton />}>
        {params.then(({ id }) => (
          <RuleDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
