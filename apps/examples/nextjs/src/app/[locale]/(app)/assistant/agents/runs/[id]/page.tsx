import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  RunDetail,
  RunDetailSkeleton,
} from "@/features/agents/components/run-detail";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function RunPage({
  params,
}: PageProps<"/[locale]/assistant/agents/runs/[id]">) {
  const t = useExtracted("agents");

  return (
    <>
      <Link
        href="/assistant/agents/runs"
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
        {params.then(({ id }) => (
          <RunDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
