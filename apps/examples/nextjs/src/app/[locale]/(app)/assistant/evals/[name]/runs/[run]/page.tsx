import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  EvalRunDetail,
  EvalRunDetailSkeleton,
} from "@/features/evals/components/eval-run-detail";
import { loadEvalParams } from "@/features/evals/evals-search-params";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the run streams in.
export const instant = true;

export default function EvalRunPage({
  params,
  searchParams,
}: PageProps<"/[locale]/assistant/evals/[name]/runs/[run]">) {
  const t = useExtracted("evals");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/assistant/evals"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All evals")}
      </Link>
      <Suspense fallback={<EvalRunDetailSkeleton />}>
        {params.then(({ name, run }) => (
          <EvalRunDetail
            name={decodeURIComponent(name)}
            runId={run}
            filters={loadEvalParams(searchParams)}
          />
        ))}
      </Suspense>
    </div>
  );
}
