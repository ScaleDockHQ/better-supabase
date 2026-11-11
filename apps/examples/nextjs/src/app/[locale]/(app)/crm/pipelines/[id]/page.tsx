import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import { SalesDetailSkeleton } from "@/features/sales/components/crm-details";
import { PipelineDetail } from "@/features/sales/components/pipeline-details";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the pipeline streams in.
export const instant = true;

export default function PipelineDetailPage({
  params,
}: PageProps<"/[locale]/crm/pipelines/[id]">) {
  const t = useExtracted("sales");

  return (
    <>
      <Link
        href="/crm/pipelines"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All pipelines")}
      </Link>
      <Suspense fallback={<SalesDetailSkeleton />}>
        {params.then(({ id }) => (
          <PipelineDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
