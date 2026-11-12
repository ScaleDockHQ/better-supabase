import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  ScoreModelDetail,
  SalesDetailSkeleton,
} from "@/features/sales/components/crm-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the model streams in.
export const instant = true;

export default function ScoreModelDetailPage({
  params,
}: PageProps<"/[locale]/crm/scoring/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/scoring"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All models")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <ScoreModelDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
