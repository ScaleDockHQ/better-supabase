import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { activeTab } from "@/components/record-detail/record-detail-tabs";
import { buttonVariants } from "@/components/ui/button";
import {
  RfqDetail,
  RfqDetailSkeleton,
} from "@/features/rfqs/components/rfq-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the request streams in behind it.
export const instant = true;

export default function RfqPage({
  params,
  searchParams,
}: PageProps<"/[locale]/rfqs/[id]">) {
  const t = useExtracted("rfqs");

  return (
    <>
      <Link
        href="/rfqs"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All requests")}
      </Link>
      <Suspense fallback={<RfqDetailSkeleton />}>
        {Promise.all([params, searchParams]).then(([{ id }, raw]) => (
          <RfqDetail
            id={id}
            tab={activeTab(raw, ["overview", "suppliers", "quotes", "compare"])}
          />
        ))}
      </Suspense>
    </>
  );
}
