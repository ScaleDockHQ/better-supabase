import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RunDetail,
  RunDetailSkeleton,
} from "@/features/workflows/components/run-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link and the run skeleton at once.
export const instant = true;

/** The back link is the static shell; the run and its steps stream in. */
export default function WorkflowRunPage({
  params,
}: PageProps<"/[locale]/workflows/runs/[run]">) {
  const t = useExtracted("workflows");

  return (
    <>
      <Link
        href="/workflows/runs"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All runs")}
      </Link>
      <Suspense fallback={<RunDetailSkeleton />}>
        {params.then(({ run }) => (
          <RunDetail run={run} />
        ))}
      </Suspense>
    </>
  );
}
