import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  EvalWorkspace,
  EvalWorkspaceSkeleton,
} from "@/features/evals/components/eval-workspace";
import { loadEvalParams } from "@/features/evals/evals-search-params";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function EvalPage({
  params,
  searchParams,
}: PageProps<"/[locale]/assistant/evals/[name]">) {
  const t = useExtracted("evals");

  return (
    <>
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
      <Suspense fallback={<EvalWorkspaceSkeleton />}>
        {params.then(({ name }) => (
          <EvalWorkspace
            name={decodeURIComponent(name)}
            filters={loadEvalParams(searchParams)}
          />
        ))}
      </Suspense>
    </>
  );
}
