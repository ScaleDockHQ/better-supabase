import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  JobRunDetail,
  JobRunDetailSkeleton,
} from "@/features/jobs/components/job-run-detail";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the run streams in.
export const instant = true;

export default function JobRunPage({
  params,
}: PageProps<"/[locale]/settings/jobs/runs/[queue]/[id]">) {
  const t = useExtracted("jobs");

  return (
    <>
      <Link
        href="/settings/jobs/runs"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All job runs")}
      </Link>
      <Suspense fallback={<JobRunDetailSkeleton />}>
        {params.then(({ queue, id }) => (
          <JobRunDetail queue={queue} id={Number(id)} />
        ))}
      </Suspense>
    </>
  );
}
