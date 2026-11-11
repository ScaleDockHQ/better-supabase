import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { SalesDetailSkeleton } from "@/features/sales/components/crm-details";
import { ForecastDetail } from "@/features/sales/components/pipeline-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the forecast streams in.
export const instant = true;

export default function ForecastDetailPage({
  params,
}: PageProps<"/[locale]/crm/forecasts/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/forecasts"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All forecasts")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <ForecastDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
