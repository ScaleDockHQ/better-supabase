import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  DefinitionDetail,
  DefinitionDetailSkeleton,
} from "@/features/workflows/components/definition-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the definition streams in.
export const instant = true;

export default function WorkflowDetailPage({
  params,
}: PageProps<"/[locale]/workflows/[definition]">) {
  const t = useExtracted("workflows");

  return (
    <div className="flex flex-col gap-4">
      <Link
        href="/workflows"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All workflows")}
      </Link>
      <Suspense fallback={<DefinitionDetailSkeleton />}>
        {params.then(({ definition }) => (
          <DefinitionDetail id={definition} />
        ))}
      </Suspense>
    </div>
  );
}
