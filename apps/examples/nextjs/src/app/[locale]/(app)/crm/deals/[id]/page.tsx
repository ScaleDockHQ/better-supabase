import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  DealDetail,
  DealDetailSkeleton,
} from "@/features/sales/components/deal-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the deal desk streams in and
// the activity tab waits for `navigation()`.
export const instant = true;

export default function DealPage({
  params,
  searchParams,
}: PageProps<"/[locale]/crm/deals/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/deals"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All deals")}
      </Link>
      <Suspense fallback={<DealDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <DealDetail id={id} tab={activeTab(raw, ["overview", "activity"])} />
        ))}
      </Suspense>
    </>
  );
}
