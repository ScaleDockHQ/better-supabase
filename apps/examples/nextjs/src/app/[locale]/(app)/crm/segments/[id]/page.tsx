import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  SegmentDetail,
  SalesDetailSkeleton,
} from "@/features/sales/components/crm-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the segment streams in.
export const instant = true;

export default function SegmentDetailPage({
  params,
}: PageProps<"/[locale]/crm/segments/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/segments"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All segments")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <SegmentDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
