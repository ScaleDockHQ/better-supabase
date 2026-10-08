import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  WorkflowRunDetail,
  WorkflowRunDetailSkeleton,
} from "@/features/workflows/components/workflow-run-detail";
import { Link } from "@/i18n/navigation";

export const instant = true;

/** The back link is the static shell; the run loads in the browser and stays live. */
export default function WorkflowRunPage({
  params,
}: PageProps<"/[locale]/workflows/[run]">) {
  const t = useExtracted("workflows");
  return (
    <>
      <Link
        href="/workflows"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All runs")}
      </Link>
      <Suspense fallback={<WorkflowRunDetailSkeleton />}>
        <WorkflowRunDetail params={params} />
      </Suspense>
    </>
  );
}
